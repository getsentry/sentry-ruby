return unless defined?(Rack)

require 'spec_helper'

RSpec.describe Sentry::Rack::CaptureExceptions, rack: true do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

  let(:transport) do
    Sentry.get_current_client.transport
  end

  describe "exceptions capturing" do
    before do
      perform_basic_setup
    end

    it 'captures the exception from direct raise' do
      app = ->(_e) { raise exception }
      stack = described_class.new(app)

      expect { stack.call(env) }.to raise_error(ZeroDivisionError)

      event = transport.events.last
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    end

    it 'captures the exception from rack.exception' do
      app = lambda do |e|
        e['rack.exception'] = exception
        [200, {}, ['okay']]
      end
      stack = described_class.new(app)

      expect do
        stack.call(env)
      end.to change { transport.events.count }.by(1)

      event = transport.events.last
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    end

    it 'captures the exception from sinatra.error' do
      app = lambda do |e|
        e['sinatra.error'] = exception
        [200, {}, ['okay']]
      end
      stack = described_class.new(app)

      stack.call(env)

      expect do
        stack.call(env)
      end.to change { transport.events.count }.by(1)

      event = transport.events.last
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    end

    it 'sets the transaction and rack env' do
      app = lambda do |e|
        e['rack.exception'] = exception
        [200, {}, ['okay']]
      end
      stack = described_class.new(app)

      stack.call(env)

      event = transport.events.last
      expect(event.transaction).to eq("/test")
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
      expect(Sentry.get_current_scope.transaction_names).to be_empty
      expect(Sentry.get_current_scope.rack_env).to eq({})
    end

    it 'passes rack/lint' do
      app = proc do
        [200, { 'Content-Type' => 'text/plain' }, ['OK']]
      end

      stack = described_class.new(Rack::Lint.new(app))
      expect { stack.call(env) }.to_not raise_error
    end

    describe "state encapsulation" do
      before do
        Sentry.configure_scope { |s| s.set_tags(tag_1: "don't change me") }
      end

      it "only contains the breadcrumbs of the request" do
        logger = ::Logger.new(nil)

        logger.info("old breadcrumb")

        request_1 = lambda do |e|
          logger.info("request breadcrumb")
          Sentry.capture_message("test")
          [200, {}, ["ok"]]
        end

        app_1 = described_class.new(request_1)

        app_1.call(env)

        event = transport.events.last
        expect(event.breadcrumbs.count).to eq(1)
        expect(event.breadcrumbs.peek.message).to eq("request breadcrumb")
      end
      it "doesn't pollute the top-level scope" do
        request_1 = lambda do |e|
          Sentry.configure_scope { |s| s.set_tags({tag_1: "foo"}) }
          Sentry.capture_message("test")
          [200, {}, ["ok"]]
        end
        app_1 = described_class.new(request_1)

        app_1.call(env)

        event = transport.events.last
        expect(event.tags).to eq(tag_1: "foo")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
      end
      it "doesn't pollute other request's scope" do
        request_1 = lambda do |e|
          Sentry.configure_scope { |s| s.set_tags({tag_1: "foo"}) }
          e['rack.exception'] = exception
          [200, {}, ["ok"]]
        end
        app_1 = described_class.new(request_1)
        app_1.call(env)

        event = transport.events.last
        expect(event.tags).to eq(tag_1: "foo")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")

        request_2 = proc do |e|
          Sentry.configure_scope { |s| s.set_tags({tag_2: "bar"}) }
          e['rack.exception'] = exception
          [200, {}, ["ok"]]
        end
        app_2 = described_class.new(request_2)
        app_2.call(env)

        event = transport.events.last
        expect(event.tags).to eq(tag_2: "bar", tag_1: "don't change me")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
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
        Sentry::Transaction.new(
          op: "pageload",
          status: "ok",
          sampled: true,
          name: "a/path"
        )
      end
      let(:stack) do
        described_class.new(
          ->(_) do
            [200, {}, ["ok"]]
          end
        )
      end

      def verify_transaction_attributes(transaction)
        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("rack.request")
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
        allow(Random).to receive(:rand).and_return(1.0)
      end

      def will_be_sampled_by_sdk
        allow(Random).to receive(:rand).and_return(0.3)
      end

      before do
        env["HTTP_SENTRY_TRACE"] = trace
      end

      let(:transaction) do
        transport.events.last
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
      end
    end

    context "when the transaction is sampled" do
      before do
        allow(Random).to receive(:rand).and_return(0.4)
      end

      it "starts a span and finishes it" do
        app = ->(_) do
          [200, {}, ["ok"]]
        end

        stack = described_class.new(app)

        stack.call(env)

        transaction = transport.events.last
        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("rack.request")
        expect(transaction.spans.count).to eq(0)
      end
    end

    context "when the transaction is not sampled" do
      before do
        allow(Random).to receive(:rand).and_return(0.6)
      end

      it "doesn't do anything" do
        app = ->(_) do
          [200, {}, ["ok"]]
        end

        stack = described_class.new(app)

        stack.call(env)

        expect(transport.events.count).to eq(0)
      end
    end

    context "when there's an exception" do
      before do
        allow(Random).to receive(:rand).and_return(0.4)
      end

      it "still finishes the transaction" do
        app = ->(_) do
          raise "foo"
        end

        stack = described_class.new(app)

        expect do
          stack.call(env)
        end.to raise_error("foo")

        expect(transport.events.count).to eq(2)
        event = transport.events.first
        transaction = transport.events.last
        expect(event.contexts.dig(:trace, :trace_id).length).to eq(32)
        expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))


        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
        expect(transaction.contexts.dig(:trace, :op)).to eq("rack.request")
        expect(transaction.spans.count).to eq(0)
      end
    end

    context "when traces_sample_rate is not set" do
      before do
        Sentry.configuration.traces_sample_rate = nil
      end

      let(:stack) do
        described_class.new(
          ->(_) do
            [200, {}, ["ok"]]
          end
        )
      end

      it "doesn't record transaction" do
        stack.call(env)

        expect(transport.events.count).to eq(0)
      end

      context "when sentry-trace header is sent" do
        let(:external_transaction) do
          Sentry::Transaction.new(
            op: "pageload",
            status: "ok",
            sampled: true,
            name: "a/path"
          )
        end

        it "doesn't cause the transaction to be recorded" do
          env["HTTP_SENTRY_TRACE"] = external_transaction.to_sentry_trace

          response = stack.call(env)

          expect(response[0]).to eq(200)
          expect(transport.events).to be_empty
        end
      end
    end
  end
end
