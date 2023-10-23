require 'spec_helper'

RSpec.describe Sentry::Transport do
  let(:io) { StringIO.new }
  let(:logger) { Logger.new(io) }
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.logger = logger
    end
  end
  let(:fake_time) { Time.now }

  let(:client) { Sentry::Client.new(configuration) }
  let(:hub) do
    Sentry::Hub.new(client, Sentry::Scope.new)
  end

  let(:dynamic_sampling_context) do
    {
      "sample_rate" => "0.01337",
      "public_key" => "49d0f7386ad645858ae85020e393bef3",
      "trace_id" => "771a43a4192642f0b136d5159a501700",
      "user_id" => "Amélie"
    }
  end

  subject { client.transport }

  describe "#serialize_envelope" do
    context "normal event" do
      let(:event) do
        event = client.event_from_exception(ZeroDivisionError.new("divided by 0"))
        event.dynamic_sampling_context = dynamic_sampling_context
        event
      end

      let(:envelope) { subject.envelope_from_event(event) }

      it "generates correct envelope content" do
        result, _ = subject.serialize_envelope(envelope)

        envelope_header, item_header, item = result.split("\n")
        envelope_header_parsed = JSON.parse(envelope_header)

        expect(envelope_header_parsed).to eq({
          "event_id" => event.event_id,
          "dsn" => Sentry::TestHelper::DUMMY_DSN,
          "sdk" => Sentry.sdk_meta,
          "sent_at" => Time.now.utc.iso8601,
          "trace" => dynamic_sampling_context
        })

        expect(item_header).to eq(
          '{"type":"event","content_type":"application/json"}'
        )

        expect(item).to eq(event.to_hash.to_json)
      end
    end

    context "transaction event" do
      let(:transaction) do
        Sentry::Transaction.new(name: "test transaction", op: "rack.request", hub: hub)
      end

      let(:event) do
        event = client.event_from_transaction(transaction)
        event.dynamic_sampling_context = dynamic_sampling_context
        event
      end

      let(:envelope) { subject.envelope_from_event(event) }

      it "generates correct envelope content" do
        result, _ = subject.serialize_envelope(envelope)

        envelope_header, item_header, item = result.split("\n")
        envelope_header_parsed = JSON.parse(envelope_header)

        expect(envelope_header_parsed).to eq({
          "event_id" => event.event_id,
          "dsn" => Sentry::TestHelper::DUMMY_DSN,
          "sdk" => Sentry.sdk_meta,
          "sent_at" => Time.now.utc.iso8601,
          "trace" => dynamic_sampling_context
        })

        expect(item_header).to eq(
          '{"type":"transaction","content_type":"application/json"}'
        )

        expect(item).to eq(event.to_hash.to_json)
      end

      context "with profiling on transaction" do
        let(:profile) do
          frames = [
            { function: "foo" },
            { function: "bar" },
            { function: "baz" }
          ]

          stacks = [
            [0, 1],
            [0, 2],
            [1, 2],
            [0, 1, 2]
          ]

          samples = [
            { stack_id: 0, elapsed_since_start_ns: 10000 },
            { stack_id: 0, elapsed_since_start_ns: 20000 },
            { stack_id: 1, elapsed_since_start_ns: 30000 },
            { stack_id: 2, elapsed_since_start_ns: 40000 },
            { stack_id: 3, elapsed_since_start_ns: 50000 }
          ]

          {
            environment: "test",
            release: "release",
            profile: {
              frames: frames,
              stacks: stacks,
              samples: samples
            }
          }
        end

        let(:event_with_profile) do
          event.profile = profile
          event
        end

        let(:envelope) { subject.envelope_from_event(event_with_profile) }

        it "adds profile item to envelope" do
          result, _ = subject.serialize_envelope(envelope)

          profile_header, profile_payload = result.split("\n").last(2)

          expect(profile_header).to eq(
            '{"type":"profile","content_type":"application/json"}'
          )

          expect(profile_payload).to eq(profile.to_json)
        end
      end
    end

    context "client report" do
      let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }
      let(:envelope) { subject.envelope_from_event(event) }
      before do
        5.times { subject.record_lost_event(:ratelimit_backoff, 'error') }
        3.times { subject.record_lost_event(:queue_overflow, 'transaction') }
      end

      it "incudes client report in envelope" do
        Timecop.travel(Time.now + 90) do
          result, _ = subject.serialize_envelope(envelope)

          client_report_header, client_report_payload = result.split("\n").last(2)

          expect(client_report_header).to eq(
            '{"type":"client_report"}'
          )

          expect(client_report_payload).to eq(
            {
              timestamp: Time.now.utc.iso8601,
              discarded_events: [
                { reason: :ratelimit_backoff, category: 'error', quantity: 5 },
                { reason: :queue_overflow, category: 'transaction', quantity: 3 }
              ]
            }.to_json
          )
        end
      end
    end

    context "oversized event" do
      context "due to breadcrumb" do
        let(:event) { client.event_from_message("foo") }
        let(:envelope) { subject.envelope_from_event(event) }

        before do
          event.breadcrumbs = Sentry::BreadcrumbBuffer.new(1000)
          1000.times do |i|
            event.breadcrumbs.record Sentry::Breadcrumb.new(category: i.to_s, message: "x" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES)
          end
          serialized_result = JSON.generate(event.to_hash)
          expect(serialized_result.bytesize).to be > Sentry::Envelope::Item::MAX_SERIALIZED_PAYLOAD_SIZE
        end

        it "removes breadcrumbs and carry on" do
          data, _ = subject.serialize_envelope(envelope)
          expect(data.bytesize).to be < Sentry::Envelope::Item::MAX_SERIALIZED_PAYLOAD_SIZE

          expect(envelope.items.count).to eq(1)

          event_item = envelope.items.first
          expect(event_item.payload[:breadcrumbs]).to be_nil
        end

        context "if it's still oversized" do
          before do
            1000.times do |i|
              event.contexts["context_#{i}"] = "s" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES
            end
          end

          it "rejects the item and logs attributes size breakdown" do
            data, _ = subject.serialize_envelope(envelope)
            expect(data).to be_nil
            expect(io.string).not_to match(/Sending envelope with items \[event\]/)
            expect(io.string).to match(/tags: 2, contexts: 8208891, extra: 2/)
          end
        end
      end

      context "due to stacktrace frames" do
        let(:event) { client.event_from_exception(SystemStackError.new("stack level too deep")) }
        let(:envelope) { subject.envelope_from_event(event) }

        let(:in_app_pattern) do
          project_root = "/fake/project_root"
          Regexp.new("^(#{project_root}/)?#{Sentry::Backtrace::APP_DIRS_PATTERN}")
        end
        let(:frame_list_limit) { 500 }
        let(:frame_list_size) { frame_list_limit * 20 }

        before do
          single_exception = event.exception.values[0]
          new_stacktrace = Sentry::StacktraceInterface.new(
            frames: frame_list_size.times.map do |zero_based_index|
              Sentry::StacktraceInterface::Frame.new(
                "/fake/path",
                Sentry::Backtrace::Line.parse("app.rb:#{zero_based_index + 1}:in `/'", in_app_pattern)
              )
            end,
          )
          single_exception.instance_variable_set(:@stacktrace, new_stacktrace)

          serialized_result = JSON.generate(event.to_hash)
          expect(serialized_result.bytesize).to be > Sentry::Envelope::Item::MAX_SERIALIZED_PAYLOAD_SIZE
        end

        it "keeps some stacktrace frames and carry on" do
          data, _ = subject.serialize_envelope(envelope)
          expect(data.bytesize).to be < Sentry::Envelope::Item::MAX_SERIALIZED_PAYLOAD_SIZE

          expect(envelope.items.count).to eq(1)

          event_item = envelope.items.first
          frames = event_item.payload[:exception][:values][0][:stacktrace][:frames]
          expect(frames.length).to eq(frame_list_limit)

          # Last N lines kept
          # N = Frame limit / 2
          expect(frames[-1][:lineno]).to eq(frame_list_size)
          expect(frames[-1][:filename]).to eq('app.rb')
          expect(frames[-1][:function]).to eq('/')
          #
          expect(frames[-(frame_list_limit / 2)][:lineno]).to eq(frame_list_size - ((frame_list_limit / 2) - 1))
          expect(frames[-(frame_list_limit / 2)][:filename]).to eq('app.rb')
          expect(frames[-(frame_list_limit / 2)][:function]).to eq('/')

          # First N lines kept
          # N = Frame limit / 2
          expect(frames[0][:lineno]).to eq(1)
          expect(frames[0][:filename]).to eq('app.rb')
          expect(frames[0][:function]).to eq('/')
          expect(frames[(frame_list_limit / 2) - 1][:lineno]).to eq(frame_list_limit / 2)
          expect(frames[(frame_list_limit / 2) - 1][:filename]).to eq('app.rb')
          expect(frames[(frame_list_limit / 2) - 1][:function]).to eq('/')
        end

        context "if it's still oversized" do
          before do
            1000.times do |i|
              event.contexts["context_#{i}"] = "s" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES
            end
          end

          it "rejects the item and logs attributes size breakdown" do
            data, _ = subject.serialize_envelope(envelope)
            expect(data).to be_nil
            expect(io.string).not_to match(/Sending envelope with items \[event\]/)
            expect(io.string).to match(/tags: 2, contexts: 8208891, extra: 2/)
          end
        end
      end
    end
  end

  describe "#send_envelope" do
    context "normal event" do
      let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }
      let(:envelope) { subject.envelope_from_event(event) }

      it "sends the event and logs the action" do
        expect(subject).to receive(:send_data)

        subject.send_envelope(envelope)

        expect(io.string).to match(/Sending envelope with items \[event\]/)
      end
    end

    context "transaction event" do
      let(:transaction) do
        Sentry::Transaction.new(name: "test transaction", op: "rack.request", hub: hub)
      end
      let(:event) { client.event_from_transaction(transaction) }
      let(:envelope) { subject.envelope_from_event(event) }

      it "sends the event and logs the action" do
        expect(subject).to receive(:send_data)

        subject.send_envelope(envelope)

        expect(io.string).to match(/Sending envelope with items \[transaction\]/)
      end
    end

    context "client report" do
      let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }
      let(:envelope) { subject.envelope_from_event(event) }
      before do
        5.times { subject.record_lost_event(:ratelimit_backoff, 'error') }
        3.times { subject.record_lost_event(:queue_overflow, 'transaction') }
      end

      it "sends the event and logs the action" do
        Timecop.travel(Time.now + 90) do
          expect(subject).to receive(:send_data)

          subject.send_envelope(envelope)

          expect(io.string).to match(/Sending envelope with items \[event, client_report\]/)
        end
      end
    end

    context "oversized event" do
      let(:event) { client.event_from_message("foo") }
      let(:envelope) { subject.envelope_from_event(event) }

      before do
        event.breadcrumbs = Sentry::BreadcrumbBuffer.new(1000)
        1000.times do |i|
          event.breadcrumbs.record Sentry::Breadcrumb.new(category: i.to_s, message: "x" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES)
        end
        serialized_result = JSON.generate(event.to_hash)
        expect(serialized_result.bytesize).to be > Sentry::Envelope::Item::MAX_SERIALIZED_PAYLOAD_SIZE
      end

      it "deletes the event's breadcrumbs and sends it" do
        expect(subject).to receive(:send_data)

        subject.send_envelope(envelope)

        expect(io.string).to match(/Sending envelope with items \[event\]/)
      end

      context "when the event hash has string keys" do
        let(:envelope) { subject.envelope_from_event(event.to_json_compatible) }

        it "deletes the event's breadcrumbs and sends it" do
          expect(subject).to receive(:send_data)

          subject.send_envelope(envelope)

          expect(io.string).to match(/Sending envelope with items \[event\]/)
        end
      end

      context "if it's still oversized" do
        before do
          1000.times do |i|
            event.contexts["context_#{i}"] = "s" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES
          end
        end

        it "rejects the event item and doesn't send the envelope" do
          expect(subject).not_to receive(:send_data)

          subject.send_envelope(envelope)

          expect(io.string).to match(/tags: 2, contexts: 8208891, extra: 2/)
          expect(io.string).not_to match(/Sending envelope with items \[event\]/)
        end

        context "with other types of items" do
          before do
            5.times { subject.record_lost_event(:ratelimit_backoff, 'error') }
            3.times { subject.record_lost_event(:queue_overflow, 'transaction') }
          end

          it "excludes oversized event and sends the rest" do
            Timecop.travel(Time.now + 90) do
              expect(subject).to receive(:send_data)

              subject.send_envelope(envelope)

              expect(io.string).to match(/Sending envelope with items \[client_report\]/)
            end
          end
        end
      end
    end
  end

  describe "#send_event" do
    let(:client) { Sentry::Client.new(configuration) }
    let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }

    context "when success" do
      before do
        allow(subject).to receive(:send_data)
      end

      it "sends Event object" do
        expect(subject).not_to receive(:failed_send)

        expect(subject.send_event(event)).to eq(event)
      end

      it "sends Event hash" do
        expect(subject).not_to receive(:failed_send)

        expect(subject.send_event(event.to_json_compatible)).to eq(event.to_json_compatible)
      end

      it "logs correct message" do
        expect(subject.send_event(event)).to eq(event)

        expect(io.string).to match(
          /INFO -- sentry: \[Transport\] Sending envelope with items \[event\] #{event.event_id} to Sentry/
        )
      end
    end

    context "when failed" do
      context "with normal error" do
        before do
          allow(subject).to receive(:send_data).and_raise(StandardError)
        end

        it "raises the error" do
          expect do
            subject.send_event(event)
          end.to raise_error(StandardError)
        end
      end

      context "with Faraday::Error" do
        it "raises the error" do
          expect do
            subject.send_event(event)
          end.to raise_error(Sentry::ExternalError)
        end
      end
    end

    context "when rate limited" do
      before do
        allow(subject).to receive(:is_rate_limited?).and_return(true)
      end

      it "records lost event" do
        subject.send_event(event)
        expect(subject).to have_recorded_lost_event(:ratelimit_backoff, 'event')
      end
    end
  end

  describe "#generate_auth_header" do
    it "generates an auth header" do
      expect(subject.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=7, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{fake_time.to_i}, " \
        "sentry_key=12345, sentry_secret=67890"
      )
    end

    it "generates an auth header without a secret (Sentry 9)" do
      configuration.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"

      expect(subject.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=7, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{fake_time.to_i}, " \
        "sentry_key=66260460f09b5940498e24bb7ce093a0"
      )
    end
  end
end
