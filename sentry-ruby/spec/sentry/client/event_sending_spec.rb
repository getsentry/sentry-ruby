require 'spec_helper'

RSpec.describe Sentry::Client do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = DUMMY_DSN
      config.transport.transport_class = Sentry::DummyTransport
    end
  end
  subject { Sentry::Client.new(configuration) }

  describe "#capture_event" do
    let(:message) { "Test message" }
    let(:scope) { Sentry::Scope.new }
    let(:event) { subject.event_from_message(message) }

    context 'with config.async set' do
      let(:async_block) do
        lambda do |event|
          subject.send_event(event)
        end
      end

      around do |example|
        prior_async = configuration.async
        configuration.async = async_block
        example.run
        configuration.async = prior_async
      end

      it "executes the given block" do
        expect(async_block).to receive(:call).and_call_original

        returned = subject.capture_event(event, scope)

        expect(returned).to be_a(Sentry::Event)
        expect(subject.transport.events.first).to eq(event.to_json_compatible)
      end

      it "doesn't call the async block if not allow sending events" do
        allow(configuration).to receive(:sending_allowed?).and_return(false)

        expect(async_block).not_to receive(:call)

        returned = subject.capture_event(event, scope)

        expect(returned).to eq(nil)
      end

      context "with false as value (the legacy way to disable it)" do
        let(:async_block) { false }

        it "doesn't cause any issue" do
          returned = subject.capture_event(event, scope, { background: false })

          expect(returned).to be_a(Sentry::Event)
          expect(subject.transport.events.first).to eq(event)
        end
      end

      context "with 2 arity block" do
        let(:async_block) do
          lambda do |event, hint|
            event["tags"]["hint"] = hint
            subject.send_event(event)
          end
        end

        it "serializes hint and supplies it as the second argument" do
          expect(configuration.async).to receive(:call).and_call_original

          returned = subject.capture_event(event, scope, { foo: "bar" })

          expect(returned).to be_a(Sentry::Event)
          event = subject.transport.events.first
          expect(event.dig("tags", "hint")).to eq({ "foo" => "bar" })
        end
      end
    end

    context "with background_worker enabled (default)" do
      before do
        Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
        configuration.before_send = lambda do |event, _hint|
          sleep 0.1
          event
        end
      end

      let(:transport) do
        subject.transport
      end

      it "sends events asynchronously" do
        subject.capture_event(event, scope)

        expect(transport.events.count).to eq(0)

        sleep(0.2)

        expect(transport.events.count).to eq(1)
      end

      context "with hint: { background: false }" do
        it "sends the event immediately" do
          subject.capture_event(event, scope, { background: false })

          expect(transport.events.count).to eq(1)
        end
      end
    end
  end

  describe "#send_event" do
    let(:event_object) do
      subject.event_from_exception(ZeroDivisionError.new("divided by 0"))
    end
    let(:transaction_event_object) do
      subject.event_from_transaction(Sentry::Transaction.new)
    end

    shared_examples "Event in send_event" do
      context "when there's an exception" do
        before do
          expect(subject.transport).to receive(:send_event).and_raise(Sentry::ExternalError.new("networking error"))
        end

        it "raises the error" do
          expect do
            subject.send_event(event)
          end.to raise_error(Sentry::ExternalError, "networking error")
        end
      end
      it "sends data through the transport" do
        expect(subject.transport).to receive(:send_event).with(event)
        subject.send_event(event)
      end

      it "applies before_send callback before sending the event" do
        configuration.before_send = lambda do |event, _hint|
          if event.is_a?(Sentry::Event)
            event.tags[:called] = true
          else
            event["tags"]["called"] = true
          end

          event
        end

        subject.send_event(event)

        if event.is_a?(Sentry::Event)
          expect(event.tags[:called]).to eq(true)
        else
          expect(event["tags"]["called"]).to eq(true)
        end
      end
    end

    it_behaves_like "Event in send_event" do
      let(:event) { event_object }
    end

    it_behaves_like "Event in send_event" do
      let(:event) { event_object.to_json_compatible }
    end

    shared_examples "TransactionEvent in send_event" do
      it "sends data through the transport" do
        subject.send_event(event)
      end

      it "doesn't apply before_send to TransactionEvent" do
        configuration.before_send = lambda do |event, _hint|
          raise "shouldn't trigger me"
        end

        subject.send_event(event)
      end
    end

    it_behaves_like "TransactionEvent in send_event" do
      let(:event) { transaction_event_object }
    end

    it_behaves_like "TransactionEvent in send_event" do
      let(:event) { transaction_event_object.to_json_compatible }
    end
  end

  describe "integrated error handling testing with HTTPTransport" do
    let(:string_io) { StringIO.new }
    let(:logger) do
      ::Logger.new(string_io)
    end
    let(:configuration) do
      Sentry::Configuration.new.tap do |config|
        config.dsn = DUMMY_DSN
        config.logger = logger
      end
    end

    let(:message) { "Test message" }
    let(:scope) { Sentry::Scope.new }
    let(:event) { subject.event_from_message(message) }

    describe "#capture_event" do
      around do |example|
        prior_async = configuration.async
        example.run
        configuration.async = prior_async
      end

      context "when scope.apply_to_event fails" do
        before do
          scope.add_event_processor do
            raise TypeError
          end
        end

        it "swallows the event and logs the failure" do
          expect(subject.capture_event(event, scope)).to be_nil

          expect(string_io.string).to match(/Event capturing failed: TypeError/)
        end
      end

      context "when sending events inline causes error" do
        before do
          configuration.background_worker_threads = 0
          Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
        end

        it "swallows and logs Sentry::ExternalError (caused by transport's networking error)" do
          expect(subject.capture_event(event, scope)).to be_nil

          expect(string_io.string).to match(/Event sending failed: Failed to open TCP connection/)
          expect(string_io.string).to match(/Unreported Event: Test message/)
          expect(string_io.string).to match(/Event capturing failed: Failed to open TCP connection/)
        end

        it "swallows and logs errors caused by the user (like in before_send)" do
          configuration.before_send = -> (_, _) { raise TypeError }

          expect(subject.capture_event(event, scope)).to be_nil

          expect(string_io.string).to match(/Event sending failed: TypeError/)
          expect(string_io.string).to match(/Unreported Event: Test message/)
        end
      end

      context "when sending events in background causes error", retry: 3 do
        before do
          Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
        end

        it "swallows and logs Sentry::ExternalError (caused by transport's networking error)" do
          expect(subject.capture_event(event, scope)).to be_a(Sentry::Event)
          sleep(0.2)

          expect(string_io.string).to match(/Event sending failed: Failed to open TCP connection/)
          expect(string_io.string).to match(/Unreported Event: Test message/)
        end

        it "swallows and logs errors caused by the user (like in before_send)" do
          configuration.before_send = -> (_, _) { raise TypeError }

          expect(subject.capture_event(event, scope)).to be_a(Sentry::Event)
          sleep(0.2)

          expect(string_io.string).to match(/Event sending failed: TypeError/)
          expect(string_io.string).to match(/Unreported Event: Test message/)
        end
      end

      context "when config.async causes error" do
        before do
          expect(subject).to receive(:send_event)
        end

        it "swallows Redis related error and send the event synchronizely" do
          class Redis
            class ConnectionError < StandardError; end
          end

          configuration.async = -> (_, _) { raise Redis::ConnectionError }

          subject.capture_event(event, scope)

          expect(string_io.string).to match(/Async event sending failed: Redis::ConnectionError/)
        end

        it "swallows and logs the exception" do
          configuration.async = -> (_, _) { raise TypeError }

          subject.capture_event(event, scope)

          expect(string_io.string).to match(/Async event sending failed: TypeError/)
        end
      end
    end

    describe "#send_event" do
      context "error happens when sending the event" do
        it "raises the error" do
          expect do
            subject.send_event(event)
          end.to raise_error(Sentry::ExternalError)

          expect(string_io.string).to match(/Event sending failed: Failed to open TCP connection/)
          expect(string_io.string).to match(/Unreported Event: Test message/)
        end
      end

      context "error happens in the before_send callback" do
        it "raises the error" do
          configuration.before_send = lambda do |event, _hint|
            raise TypeError
          end

          expect do
            subject.send_event(event)
          end.to raise_error(TypeError)

          expect(string_io.string).to match(/Event sending failed: TypeError/)
          expect(string_io.string).to match(/Unreported Event: Test message/)
        end
      end
    end
  end
end
