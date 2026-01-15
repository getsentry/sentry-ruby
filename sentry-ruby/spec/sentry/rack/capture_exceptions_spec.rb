# frozen_string_literal: true

require 'sentry/vernier/profiler'

RSpec.describe 'Sentry::Rack::CaptureExceptions', when: :rack_available? do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

  describe "exceptions capturing" do
    before do
      perform_basic_setup
    end

    it 'captures the exception from direct raise' do
      app = ->(_e) { raise exception }
      stack = Sentry::Rack::CaptureExceptions.new(app)

      expect { stack.call(env) }.to raise_error(ZeroDivisionError)

      event = last_sentry_event.to_h
      expect(event.dig(:request, :url)).to eq("http://example.org/test")
      expect(env["sentry.error_event_id"]).to eq(event[:event_id])
      last_frame = event.dig(:exception, :values, 0, :stacktrace, :frames).last
      expect(last_frame[:vars]).to eq(nil)
    end

    it 'has the correct mechanism' do
      app = ->(_e) { raise exception }
      stack = Sentry::Rack::CaptureExceptions.new(app)

      expect { stack.call(env) }.to raise_error(ZeroDivisionError)

      event = last_sentry_event.to_h
      mechanism = event.dig(:exception, :values, 0, :mechanism)
      expect(mechanism).to eq({ type: 'rack', handled: false })
    end

    it 'captures the exception from rack.exception' do
      app = lambda do |e|
        e['rack.exception'] = exception
        [200, {}, ['okay']]
      end
      stack = Sentry::Rack::CaptureExceptions.new(app)

      expect do
        stack.call(env)
      end.to change { sentry_events.count }.by(1)

      event = last_sentry_event
      expect(env["sentry.error_event_id"]).to eq(event.event_id)
      expect(event.to_h.dig(:request, :url)).to eq("http://example.org/test")
    end

    it 'captures the exception from sinatra.error' do
      app = lambda do |e|
        e['sinatra.error'] = exception
        [200, {}, ['okay']]
      end
      stack = Sentry::Rack::CaptureExceptions.new(app)

      expect do
        stack.call(env)
      end.to change { sentry_events.count }.by(1)

      event = last_sentry_event
      expect(event.to_h.dig(:request, :url)).to eq("http://example.org/test")
    end

    it 'sets the transaction and rack env' do
      app = lambda do |e|
        e['rack.exception'] = exception
        [200, {}, ['okay']]
      end
      stack = Sentry::Rack::CaptureExceptions.new(app)

      stack.call(env)

      event = last_sentry_event
      expect(event.transaction).to eq("/test")
      expect(event.to_h.dig(:request, :url)).to eq("http://example.org/test")
      expect(Sentry.get_current_scope.transaction_name).to be_nil
      expect(Sentry.get_current_scope.rack_env).to eq({})
    end

    it 'passes rack/lint' do
      app = proc do
        [200, { 'content-type' => 'text/plain' }, ['OK']]
      end

      stack = Sentry::Rack::CaptureExceptions.new(Rack::Lint.new(app))
      expect { stack.call(env) }.to_not raise_error
      expect(env.key?("sentry.error_event_id")).to eq(false)
    end

    context "with config.include_local_variables = true" do
      before do
        perform_basic_setup do |config|
          config.include_local_variables = true
        end
      end

      after do
        Sentry.exception_locals_tp.disable
      end

      it 'captures the exception with locals' do
        app = ->(_e) do
          a = 1
          b = 0
          a / b
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        expect { stack.call(env) }.to raise_error(ZeroDivisionError)

        event = last_sentry_event.to_h
        expect(event.dig(:request, :url)).to eq("http://example.org/test")
        last_frame = event.dig(:exception, :values, 0, :stacktrace, :frames).last
        expect(last_frame[:vars]).to include({ a: "1", b: "0" })
      end

      it 'ignores problematic locals' do
        class Foo
          def inspect
            raise
          end
        end

        app = ->(_e) do
          a = 1
          b = 0
          f = Foo.new
          a / b
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        expect { stack.call(env) }.to raise_error(ZeroDivisionError)

        event = last_sentry_event.to_h
        expect(event.dig(:request, :url)).to eq("http://example.org/test")
        last_frame = event.dig(:exception, :values, 0, :stacktrace, :frames).last
        expect(last_frame[:vars]).to include({ a: "1", b: "0", f: "[ignored due to error]" })
      end

      it 'truncates lengthy values' do
        app = ->(_e) do
          a = 1
          b = 0
          long = "*" * 2000
          a / b
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        expect { stack.call(env) }.to raise_error(ZeroDivisionError)

        event = last_sentry_event.to_h
        expect(event.dig(:request, :url)).to eq("http://example.org/test")
        last_frame = event.dig(:exception, :values, 0, :stacktrace, :frames).last
        expect(last_frame[:vars]).to include({ a: "1", b: "0", long: "*" * 1024 + "..." })
      end
    end

    describe "state encapsulation" do
      before do
        Sentry.configure_scope { |s| s.set_tags(tag_1: "don't change me") }
        Sentry.configuration.breadcrumbs_logger = [:sentry_logger]
      end

      it "only contains the breadcrumbs of the request" do
        logger = ::Logger.new(nil)

        logger.info("old breadcrumb")

        request_1 = lambda do |e|
          logger.info("request breadcrumb")
          Sentry.capture_message("test")
          [200, {}, ["ok"]]
        end

        app_1 = Sentry::Rack::CaptureExceptions.new(request_1)

        app_1.call(env)

        event = last_sentry_event
        expect(event.breadcrumbs.count).to eq(1)
        expect(event.breadcrumbs.peek.message).to eq("request breadcrumb")
      end
      it "doesn't pollute the top-level scope" do
        request_1 = lambda do |e|
          Sentry.configure_scope { |s| s.set_tags({ tag_1: "foo" }) }
          Sentry.capture_message("test")
          [200, {}, ["ok"]]
        end
        app_1 = Sentry::Rack::CaptureExceptions.new(request_1)

        app_1.call(env)

        event = last_sentry_event
        expect(event.tags).to eq(tag_1: "foo")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
      end
      it "doesn't pollute other request's scope" do
        request_1 = lambda do |e|
          Sentry.configure_scope { |s| s.set_tags({ tag_1: "foo" }) }
          e['rack.exception'] = Exception.new
          [200, {}, ["ok"]]
        end
        app_1 = Sentry::Rack::CaptureExceptions.new(request_1)
        app_1.call(env)

        event = last_sentry_event
        expect(event.tags).to eq(tag_1: "foo")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")

        request_2 = proc do |e|
          Sentry.configure_scope { |s| s.set_tags({ tag_2: "bar" }) }
          e['rack.exception'] = Exception.new
          [200, {}, ["ok"]]
        end
        app_2 = Sentry::Rack::CaptureExceptions.new(request_2)
        app_2.call(env)

        event = last_sentry_event
        expect(event.tags).to eq(tag_2: "bar", tag_1: "don't change me")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
      end
    end

    context "with send_default_pii" do
      before do
        perform_basic_setup do |config|
          config.send_default_pii = true
        end
      end

      context "with form data" do
        let(:additional_headers) do
          { "REQUEST_METHOD" => "POST", ::Rack::RACK_INPUT => StringIO.new("foo=bar") }
        end

        it "captures the exception with request form data" do
          app = ->(_e) { raise exception }
          stack = Sentry::Rack::CaptureExceptions.new(app)

          expect { stack.call(env) }.to raise_error(ZeroDivisionError)

          event = last_sentry_event.to_h
          expect(event.dig(:request, :url)).to eq("http://example.org/test")
          expect(event.dig(:request, :data)).to eq({ "foo" => "bar" })
        end

        it "allows later middlewares to read body" do
          app = ->(_e) { raise exception }
          stack = Sentry::Rack::CaptureExceptions.new(app)

          expect { stack.call(env) }.to raise_error(ZeroDivisionError)
          expect { ::Rack::Request.new(env).body.read }.not_to raise_error
        end
      end

      context "with rewindable non form data" do
        let(:additional_headers) do
          { "REQUEST_METHOD" => "POST", "CONTENT_TYPE" => "application/text", ::Rack::RACK_INPUT => StringIO.new("stuff") }
        end

        it "captures the exception with request form data" do
          app = ->(_e) { raise exception }
          stack = Sentry::Rack::CaptureExceptions.new(app)

          expect { stack.call(env) }.to raise_error(ZeroDivisionError)

          event = last_sentry_event.to_h
          expect(event.dig(:request, :url)).to eq("http://example.org/test")
          expect(event.dig(:request, :data)).to eq("stuff")
        end

        it "allows later middlewares to read body" do
          app = ->(_e) { raise exception }
          stack = Sentry::Rack::CaptureExceptions.new(app)

          expect { stack.call(env) }.to raise_error(ZeroDivisionError)
          expect { ::Rack::Request.new(env).body.read }.not_to raise_error
        end
      end

      context "with non rewindable non form data" do
        let(:dbl) { double }
        let(:additional_headers) do
          { "REQUEST_METHOD" => "POST", "CONTENT_TYPE" => "application/text", ::Rack::RACK_INPUT => dbl }
        end

        it "does not try to read non rewindable body" do
          app = ->(_e) { raise exception }
          stack = Sentry::Rack::CaptureExceptions.new(app)

          expect { stack.call(env) }.to raise_error(ZeroDivisionError)

          event = last_sentry_event.to_h
          expect(event.dig(:request, :url)).to eq("http://example.org/test")
          expect(event.dig(:request, :data)).to eq("Skipped non-rewindable request body")
        end

        it "allows later middlewares to read body" do
          allow(dbl).to receive(:read)

          app = ->(_e) { raise exception }
          stack = Sentry::Rack::CaptureExceptions.new(app)

          expect { stack.call(env) }.to raise_error(ZeroDivisionError)
          expect { ::Rack::Request.new(env).body.read }.not_to raise_error
        end
      end
    end
  end

  describe "performance monitoring" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 0.5
      end
    end

    context "when sentry-trace header is sent" do
      let(:external_transaction) do
        Sentry.start_transaction(
          op: "pageload",
          status: "ok",
          sampled: true,
          name: "a/path",
        )
      end

      let(:stack) do
        Sentry::Rack::CaptureExceptions.new(
          ->(_) do
            [200, {}, ["ok"]]
          end
        )
      end

      def verify_transaction_attributes(transaction)
        expect(transaction.type).to eq("transaction")
        expect(transaction.transaction).to eq("/test")
        expect(transaction.transaction_info).to eq({ source: :url })
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("http.server")
        expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.http.rack")
        expect(transaction.spans.count).to eq(0)
      end

      def verify_transaction_inherits_external_transaction(transaction, external_transaction)
        expect(transaction.contexts.dig(:trace, :trace_id)).to eq(external_transaction.trace_id)
        expect(transaction.contexts.dig(:trace, :parent_span_id)).to eq(external_transaction.span_id)
      end

      def verify_transaction_doesnt_inherit_external_transaction(transaction, external_transaction)
        expect(transaction.contexts.dig(:trace, :trace_id)).not_to eq(external_transaction.trace_id)
        expect(transaction.contexts.dig(:trace, :parent_span_id)).not_to eq(external_transaction.span_id)
      end

      def wont_be_sampled_by_sdk
        allow_any_instance_of(Sentry::Utils::SampleRand).to receive(:generate_from_trace_id).and_return(1.0)
      end

      def will_be_sampled_by_sdk
        allow_any_instance_of(Sentry::Utils::SampleRand).to receive(:generate_from_trace_id).and_return(0.3)
      end

      before do
        env["HTTP_SENTRY_TRACE"] = trace
      end

      let(:transaction) do
        last_sentry_event
      end

      context "with sampled trace" do
        let(:trace) do
          "#{external_transaction.trace_id}-#{external_transaction.span_id}-1"
        end

        it "inherits trace info and sampled decision from the trace and ignores later sampling" do
          wont_be_sampled_by_sdk

          stack.call(env)

          verify_transaction_attributes(transaction)
          verify_transaction_inherits_external_transaction(transaction, external_transaction)
        end
      end

      context "with unsampled trace" do
        let(:trace) do
          "#{external_transaction.trace_id}-#{external_transaction.span_id}-0"
        end

        it "doesn't sample any transaction" do
          will_be_sampled_by_sdk

          stack.call(env)

          expect(transaction).to be_nil
        end
      end

      context "with trace that has no sampling bit" do
        let(:trace) do
          "#{external_transaction.trace_id}-#{external_transaction.span_id}-"
        end

        it "inherits trace info but not the sampling decision (later sampled)" do
          will_be_sampled_by_sdk

          stack.call(env)

          verify_transaction_attributes(transaction)
          verify_transaction_inherits_external_transaction(transaction, external_transaction)
        end

        it "inherits trace info but not the sampling decision (later unsampled)" do
          wont_be_sampled_by_sdk

          stack.call(env)

          expect(transaction).to eq(nil)
        end
      end

      context "with bugus trace" do
        let(:trace) { "null" }

        it "starts a new transaction and follows SDK sampling decision (sampled)" do
          will_be_sampled_by_sdk

          stack.call(env)

          verify_transaction_attributes(transaction)
          verify_transaction_doesnt_inherit_external_transaction(transaction, external_transaction)
        end

        it "starts a new transaction and follows SDK sampling decision (unsampled)" do
          wont_be_sampled_by_sdk

          stack.call(env)

          expect(transaction).to eq(nil)
        end
      end

      context "when traces_sampler is set" do
        let(:trace) do
          "#{external_transaction.trace_id}-#{external_transaction.span_id}-1"
        end

        it "passes parent_sampled to the sampling_context" do
          parent_sampled = false

          Sentry.configuration.traces_sampler = lambda do |sampling_context|
            parent_sampled = sampling_context[:parent_sampled]
          end

          stack.call(env)

          expect(parent_sampled).to eq(true)
        end

        it "passes request env to the sampling_context" do
          sampling_context_env = nil

          Sentry.configuration.traces_sampler = lambda do |sampling_context|
            sampling_context_env = sampling_context[:env]
          end

          stack.call(env)

          expect(sampling_context_env).to eq(env)
        end
      end

      context "when the baggage header is sent" do
        let(:trace) do
          "#{external_transaction.trace_id}-#{external_transaction.span_id}-1"
        end

        before do
          env["HTTP_BAGGAGE"] = "other-vendor-value-1=foo;bar;baz, "\
            "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
            "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
            "sentry-sample_rate=0.01337, "\
            "sentry-user_id=Am%C3%A9lie,  "\
            "other-vendor-value-2=foo;bar;"
        end

        it "has the dynamic_sampling_context on the TransactionEvent" do
          expect(Sentry::Transaction).to receive(:new).
            with(hash_including(:baggage)).
            and_call_original

          stack.call(env)

          expect(transaction.dynamic_sampling_context).to eq({
            "sample_rate" => "0.01337",
            "public_key" => "49d0f7386ad645858ae85020e393bef3",
            "trace_id" => "771a43a4192642f0b136d5159a501700",
            "user_id" => "Amélie"
          })
        end
      end
    end

    context "when the transaction is sampled" do
      before do
        allow_any_instance_of(Sentry::Utils::SampleRand).to receive(:generate_from_trace_id).and_return(0.4)
      end

      it "starts a transaction and finishes it" do
        app = ->(_) do
          [200, {}, ["ok"]]
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        stack.call(env)

        transaction = last_sentry_event
        expect(transaction.type).to eq("transaction")
        expect(transaction.transaction).to eq("/test")
        expect(transaction.transaction_info).to eq({ source: :url })
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("http.server")
        expect(transaction.spans.count).to eq(0)
      end

      describe "Sentry.with_child_span" do
        it "sets nested spans correctly under the request's transaction" do
          app = ->(_) do
            Sentry.with_child_span(op: "first level") do
              Sentry.with_child_span(op: "second level") do
                [200, {}, ["ok"]]
              end
            end
          end

          stack = Sentry::Rack::CaptureExceptions.new(app)

          stack.call(env)

          transaction = last_sentry_event
          expect(transaction.type).to eq("transaction")
          expect(transaction.timestamp).not_to be_nil
          expect(transaction.transaction).to eq("/test")
          expect(transaction.transaction_info).to eq({ source: :url })
          expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
          expect(transaction.contexts.dig(:trace, :op)).to eq("http.server")
          expect(transaction.spans.count).to eq(2)

          first_span = transaction.spans.first
          expect(first_span[:op]).to eq("first level")
          expect(first_span[:parent_span_id]).to eq(transaction.contexts.dig(:trace, :span_id))

          second_span = transaction.spans.last
          expect(second_span[:op]).to eq("second level")
          expect(second_span[:parent_span_id]).to eq(first_span[:span_id])
        end
      end
    end

    context "when the transaction is not sampled" do
      before do
        allow_any_instance_of(Sentry::Utils::SampleRand).to receive(:generate_from_trace_id).and_return(1.0)
      end

      it "doesn't do anything" do
        app = ->(_) do
          [200, {}, ["ok"]]
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        stack.call(env)

        expect(sentry_events.count).to eq(0)
      end
    end

    context "when there's an exception" do
      before do
        allow_any_instance_of(Sentry::Utils::SampleRand).to receive(:generate_from_trace_id).and_return(0.4)
      end

      it "still finishes the transaction" do
        app = ->(_) do
          raise "foo"
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        expect do
          stack.call(env)
        end.to raise_error("foo")

        expect(sentry_events.count).to eq(2)
        event = sentry_events.first
        transaction = last_sentry_event
        expect(event.contexts.dig(:trace, :trace_id).length).to eq(32)
        expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))

        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
        expect(transaction.contexts.dig(:trace, :op)).to eq("http.server")
        expect(transaction.spans.count).to eq(0)
      end
    end

    context "when traces_sample_rate is not set" do
      before do
        Sentry.configuration.traces_sample_rate = nil
      end

      let(:stack) do
        Sentry::Rack::CaptureExceptions.new(
          ->(_) do
            [200, {}, ["ok"]]
          end
        )
      end

      it "doesn't record transaction" do
        stack.call(env)

        expect(sentry_events.count).to eq(0)
      end

      context "when sentry-trace header is sent" do
        let(:external_transaction) do
          Sentry::Transaction.new(
            op: "pageload",
            status: "ok",
            sampled: true,
            name: "a/path",
          )
        end

        it "doesn't cause the transaction to be recorded" do
          env["HTTP_SENTRY_TRACE"] = external_transaction.to_sentry_trace

          response = stack.call(env)

          expect(response[0]).to eq(200)
          expect(sentry_events).to be_empty
        end
      end
    end
  end

  describe "queue time capture" do
    let(:stack) do
      app = ->(_) { [200, {}, ['ok']] }
      Sentry::Rack::CaptureExceptions.new(app)
    end

    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
      end
    end

    let(:transaction) { last_sentry_event }

    context "with X-Request-Start header" do
      it "attaches queue time to transaction" do
        timestamp = Time.now.to_f - 0.05  # 50ms ago
        env["HTTP_X_REQUEST_START"] = "t=#{timestamp}"

        stack.call(env)

        queue_time = transaction.contexts.dig(:trace, :data, 'http.server.request.time_in_queue')
        expect(queue_time).to be_within(10).of(50)
      end

      it "subtracts puma.request_body_wait" do
        Timecop.freeze do
          timestamp = Time.now.to_f - 0.1  # 100ms ago
          env["HTTP_X_REQUEST_START"] = "t=#{timestamp}"
          env["puma.request_body_wait"] = 40  # 40ms waiting for client

          stack.call(env)

          queue_time = transaction.contexts.dig(:trace, :data, 'http.server.request.time_in_queue')
          expect(queue_time).to be_within(10).of(60)  # 100 - 40
        end
      end

      it "handles different timestamp formats" do
        # Heroku/HAProxy microseconds format
        timestamp_us = ((Time.now.to_f - 0.03) * 1_000_000).to_i
        env["HTTP_X_REQUEST_START"] = "t=#{timestamp_us}"

        stack.call(env)

        queue_time = transaction.contexts.dig(:trace, :data, 'http.server.request.time_in_queue')
        expect(queue_time).to be_within(10).of(30)
      end
    end

    context "without X-Request-Start header" do
      it "doesn't add queue time data" do
        stack.call(env)

        queue_time = transaction.contexts.dig(:trace, :data, 'http.server.request.time_in_queue')
        expect(queue_time).to be_nil
      end
    end

    context "with invalid header" do
      it "doesn't add queue time data" do
        env["HTTP_X_REQUEST_START"] = "invalid"

        stack.call(env)

        queue_time = transaction.contexts.dig(:trace, :data, 'http.server.request.time_in_queue')
        expect(queue_time).to be_nil
      end
    end

    context "when capture_queue_time is disabled" do
      before do
        Sentry.configuration.capture_queue_time = false
      end

      it "doesn't capture queue time" do
        timestamp = Time.now.to_f - 0.05
        env["HTTP_X_REQUEST_START"] = "t=#{timestamp}"

        stack.call(env)

        queue_time = transaction.contexts.dig(:trace, :data, 'http.server.request.time_in_queue')
        expect(queue_time).to be_nil
      end
    end
  end

  describe "tracing without performance" do
    let(:incoming_prop_context) { Sentry::PropagationContext.new(Sentry::Scope.new) }
    let(:env) do
      {
        "HTTP_SENTRY_TRACE" => incoming_prop_context.get_traceparent,
        "HTTP_BAGGAGE" => incoming_prop_context.get_baggage.serialize
      }
    end

    let(:stack) do
      app = ->(_e) { raise exception }
      Sentry::Rack::CaptureExceptions.new(app)
    end

    before { perform_basic_setup }

    it "captures exception with correct DSC and trace context" do
      expect { stack.call(env) }.to raise_error(ZeroDivisionError)

      trace_context = last_sentry_event.contexts[:trace]
      expect(trace_context[:trace_id]).to eq(incoming_prop_context.trace_id)
      expect(trace_context[:parent_span_id]).to eq(incoming_prop_context.span_id)
      expect(trace_context[:span_id].length).to eq(16)

      expect(last_sentry_event.dynamic_sampling_context).to eq(incoming_prop_context.get_dynamic_sampling_context)
    end
  end

  describe "session capturing" do
    context "when auto_session_tracking is false" do
      before do
        perform_basic_setup do |config|
          config.auto_session_tracking = false
        end
      end

      it "passthrough" do
        app = ->(_) do
          [200, {}, ["ok"]]
        end

        expect_any_instance_of(Sentry::Hub).not_to receive(:start_session)
        expect(Sentry.session_flusher).to be_nil
        stack = Sentry::Rack::CaptureExceptions.new(app)
        stack.call(env)

        expect(sentry_envelopes.count).to eq(0)
      end
    end

    context "tracks sessions by default" do
      before do
        perform_basic_setup do |config|
          config.release = 'test-release'
          config.environment = 'test'
        end
      end

      it "collects session stats and sends envelope with aggregated sessions" do
        app = lambda do |env|
          req = Rack::Request.new(env)
          case req.path_info
          when /success/
            [200, {}, ['ok']]
          when /error/
            1 / 0
          end
        end

        stack = Sentry::Rack::CaptureExceptions.new(app)

        expect(Sentry.session_flusher).not_to be_nil

        now = Time.now.utc
        now_bucket = Time.utc(now.year, now.month, now.day, now.hour, now.min)

        Timecop.freeze(now) do
          10.times do
            env = Rack::MockRequest.env_for('/success')
            stack.call(env)
          end

          2.times do
            env = Rack::MockRequest.env_for('/error')
            expect { stack.call(env) }.to raise_error(ZeroDivisionError)
          end

          expect(sentry_events.count).to eq(2)

          Sentry.session_flusher.flush

          expect(sentry_envelopes.count).to eq(3)

          session_envelope = sentry_envelopes.find do |envelope|
            envelope.items.any? { |item| item.type == 'sessions' }
          end

          expect(session_envelope).not_to be_nil
          expect(session_envelope.items.length).to eq(1)
          item = session_envelope.items.first
          expect(item.type).to eq('sessions')
          expect(item.payload[:attrs]).to eq({ release: 'test-release', environment: 'test' })
          expect(item.payload[:aggregates].first).to eq({ exited: 10, errored: 2, started: now_bucket.iso8601 })
        end
      end
    end
  end

  shared_examples "a profiled transaction" do
    it "collects a profile", retry: 3 do
      stack = Sentry::Rack::CaptureExceptions.new(app)
      stack.call(env)
      event = last_sentry_event

      profile = event.profile
      expect(profile).not_to be_nil

      expect(profile[:event_id]).not_to be_nil
      expect(profile[:platform]).to eq("ruby")
      expect(profile[:version]).to eq("1")
      expect(profile[:environment]).to eq("development")
      expect(profile[:release]).to eq("test-release")
      expect { Time.parse(profile[:timestamp]) }.not_to raise_error

      expect(profile[:device]).to include(:architecture)
      expect(profile[:os]).to include(:name, :version)
      expect(profile[:runtime]).to include(:name, :version)

      expect(profile[:transaction]).to include(:id, :name, :trace_id, :active_thread_id)
      expect(profile[:transaction][:id]).to eq(event.event_id)
      expect(profile[:transaction][:name]).to eq(event.transaction)
      expect(profile[:transaction][:trace_id]).to eq(event.contexts[:trace][:trace_id])

      thread_id_mapping = {
        Sentry::Profiler => "0",
        Sentry::Vernier::Profiler => Thread.current.object_id.to_s
      }

      expect(profile[:transaction][:active_thread_id]).to eq(thread_id_mapping[Sentry.configuration.profiler_class])

      # detailed checking of content is done in profiler_spec,
      # just check basic structure here
      frames = profile[:profile][:frames]
      expect(frames).to be_a(Array)
      expect(frames.first).to include(:function, :filename, :abs_path, :in_app)

      stacks = profile[:profile][:stacks]
      expect(stacks).to be_a(Array)
      expect(stacks.first).to be_a(Array)
      expect(stacks.first.first).to be_a(Integer)

      samples = profile[:profile][:samples]
      expect(samples).to be_a(Array)
      expect(samples.first).to include(:stack_id, :thread_id, :elapsed_since_start_ns)
    end
  end

  describe "profiling with StackProf", when: [:stack_prof_installed?, :rack_available?] do
    context "when profiling is enabled" do
      let(:app) do
         ->(_) do
          [200, {}, "ok"]
        end
      end

      let(:stackprof_results) do
        data = StackProf::Report.from_file('spec/support/stackprof_results.json').data
        # relative dir differs on each machine
        data[:frames].each { |_id, fra| fra[:file].gsub!(/<dir>/, Dir.pwd) }
        data
      end

      before do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.profiles_sample_rate = 1.0
          config.release = "test-release"
        end

        StackProf.stop

        allow(StackProf).to receive(:results).and_return(stackprof_results)
      end

      include_examples "a profiled transaction"
    end
  end

  describe "profiling with vernier", when: [:vernier_installed?, :rack_available?] do
    context "when profiling is enabled" do
      let(:app) do
         ->(_) do
          ProfilerTest::Bar.bar
          [200, {}, "ok"]
        end
      end

      before do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.profiles_sample_rate = 1.0
          config.release = "test-release"
          config.profiler_class = Sentry::Vernier::Profiler
          config.project_root = Dir.pwd
        end
      end

      include_examples "a profiled transaction"
    end
  end
end
