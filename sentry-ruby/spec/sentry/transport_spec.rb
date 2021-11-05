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
    Sentry::Hub.new(client, subject)
  end

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
        Sentry::Transaction.new(name: "test transaction", op: "rack.request", hub: hub)
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

    context "client report" do
      let(:event) { client.event_from_exception(ZeroDivisionError.new("divided by 0")) }
      before do
        5.times { subject.record_lost_event(:ratelimit_backoff, 'error') }
        3.times { subject.record_lost_event(:queue_overflow, 'transaction') }
      end

      it "incudes client report in envelope" do
        Timecop.travel(Time.now + 90) do
          result = subject.encode(event.to_hash)

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

    context "when rate limited" do
      before do
        allow(subject).to receive(:is_rate_limited?).and_return(true)
      end

      it "records lost event" do
        expect(subject).to receive(:record_lost_event).with(:ratelimit_backoff, 'event')
        subject.send_event(event)
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
