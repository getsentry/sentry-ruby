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
  subject { client.transport }

  describe "#encode" do

    before do
      Sentry.init do |config|
        config.dsn = DUMMY_DSN
      end
    end

    context "normal event" do
      let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }
      it "generates correct envelope content" do
        result = subject.encode(event.to_hash)

        envelope_header, item_header, item = result.split("\n")

        expect(envelope_header).to eq(
          <<~ENVELOPE_HEADER.chomp
            {"event_id":"#{event.event_id}","dsn":"#{DUMMY_DSN}","sdk":#{Sentry.sdk_meta.to_json},"sent_at":"#{Time.now.utc.iso8601}"}
          ENVELOPE_HEADER
        )

        expect(item_header).to eq(
          '{"type":"event","content_type":"application/json"}'
        )

        expect(item).to eq(event.to_hash.to_json)
      end
    end

    context "transaction event" do
      let(:transaction) do
        Sentry::Transaction.new(name: "test transaction", op: "rack.request")
      end
      let(:event) do
        client.event_from_transaction(transaction)
      end

      it "generates correct envelope content" do
        result = subject.encode(event.to_hash)

        envelope_header, item_header, item = result.split("\n")

        expect(envelope_header).to eq(
          <<~ENVELOPE_HEADER.chomp
            {"event_id":"#{event.event_id}","dsn":"#{DUMMY_DSN}","sdk":#{Sentry.sdk_meta.to_json},"sent_at":"#{Time.now.utc.iso8601}"}
          ENVELOPE_HEADER
        )

        expect(item_header).to eq(
          '{"type":"transaction","content_type":"application/json"}'
        )

        expect(item).to eq(event.to_hash.to_json)
      end
    end
  end

  describe "#send_event" do
    let(:client) { Sentry::Client.new(configuration) }
    let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }

    context "when event is not allowed (by sampling)" do
      let(:string_io) do
        StringIO.new
      end

      before do
        configuration.logger = Logger.new(string_io)
        configuration.sample_rate = 0.5
        allow(Random::DEFAULT).to receive(:rand).and_return(0.6)
      end

      it "logs correct message" do
        subject.send_event(event)

        logs = string_io.string
        expect(logs).to match(/Event not sent: Excluded by random sample/)
      end
    end

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
          /INFO -- sentry: Sending envelope \[event\] #{event.event_id} to Sentry/
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
