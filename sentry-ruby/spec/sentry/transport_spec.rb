require 'spec_helper'

RSpec.describe Sentry::Transports::Transport do
  let(:logger) { Logger.new(nil) }
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.logger = logger
    end
  end
  let(:fake_time) { Time.now }

  subject { described_class.new(configuration) }

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
        expect(logger).to receive(:info).with("Sending event #{event.id} to Sentry")

        expect(subject.send_event(event)).to eq(event)
      end

      it "sets the correct state" do
        expect(subject.state).to receive(:success)

        subject.send_event(event)

        expect(subject.state).not_to be_failed
      end
    end

    context "when failed" do
      before do
        allow(subject).to receive(:send_data).and_raise(StandardError)

        expect(logger).to receive(:warn).exactly(2).and_call_original
      end

      it "returns nil" do
        expect(subject.send_event(event)).to eq(nil)
      end

      it "changes the statreturns nile to fail" do
        expect(subject.state).to receive(:failure).and_call_original

        subject.send_event(event)

        expect(subject.state).to be_failed
      end
    end

    context "should_try? is false" do
      before do
        allow(subject.state).to receive(:should_try?).and_return(false)
      end

      it "doesn't change the state" do
        expect(logger).to receive(:warn).with("Not sending event due to previous failure(s).").ordered
        expect(logger).to receive(:warn).with("Failed to submit event: ZeroDivisionError: divided by 0").ordered
        expect(subject.state).not_to receive(:failure)

        expect(subject.send_event(event)).to eq(nil)
      end
    end

    describe 'async' do
      let(:message) { "Test message" }

      around do |example|
        prior_async = configuration.async
        configuration.async = proc { :ok }
        example.run
        configuration.async = prior_async
      end

      before do
        allow(subject).to receive(:send_data)
      end

      it "doesn't send the event right away" do
        expect(configuration.async).to receive(:call)

        returned = subject.send_event(event)

        expect(returned).to be_a(Sentry::Event)
      end

      context "when async raises an exception" do
        around do |example|
          prior_async = configuration.async
          configuration.async = proc { raise TypeError }
          example.run
          configuration.async = prior_async
        end

        it 'sends the result of Event.capture_exception via fallback' do
          expect(logger).to receive(:error).with("async event sending failed: TypeError")
          expect(configuration.async).to receive(:call).and_call_original
          expect(subject).to receive(:send_data)

          subject.send_event(event)
        end
      end
    end
  end

  describe "#generate_auth_header" do
    it "generates an auth header" do
      expect(subject.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{fake_time.to_i}, " \
        "sentry_key=12345, sentry_secret=67890"
      )
    end

    it "generates an auth header without a secret (Sentry 9)" do
      configuration.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"

      expect(subject.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{fake_time.to_i}, " \
        "sentry_key=66260460f09b5940498e24bb7ce093a0"
      )
    end
  end
end
