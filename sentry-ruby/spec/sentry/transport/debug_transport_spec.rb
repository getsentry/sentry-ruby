# frozen_string_literal: true

RSpec.describe Sentry do
  let(:client) { Sentry.get_current_client }
  let(:transport) { Sentry.get_current_client.transport }
  let(:error) { StandardError.new("test error") }

  before do
    perform_basic_setup

    setup_sentry_test do |config|
      config.dsn = dsn
      config.transport.transport_class = Sentry::DebugTransport
      config.debug = true
    end
  end

  after do
    teardown_sentry_test
  end

  context "with local DSN for testing" do
    let(:dsn) { Sentry::TestHelper::DUMMY_DSN }

    def build_envelope(body)
      Sentry::Envelope.new(sent_at: Sentry.utc_now.iso8601).tap do |envelope|
        envelope.add_item({ type: "log" }, { items: [{ body: body }] })
      end
    end

    describe ".capture_exception with debug transport" do
      it "logs envelope data and stores an event internally" do
        Sentry.capture_exception(error)

        expect(transport.events.count).to be(1)
        expect(transport.backend.events.count).to be(1)
        expect(transport.backend.envelopes.count).to be(1)

        event = transport.logged_envelopes.last
        item = event["items"].first
        payload = item["payload"]

        expect(payload["exception"]["values"].first["value"]).to include("test error")
      end
    end

    describe "#send_envelope" do
      it "logs the envelope and passes it on to the backend" do
        transport.send_envelope(build_envelope("hello"))

        expect(transport.backend.envelopes.count).to be(1)
        expect(transport.logged_envelopes.last.dig("items", 0, "payload", "items", 0, "body")).to eq("hello")
      end
    end

    describe "#logged_envelopes" do
      it "skips a last line that is still being written" do
        transport.clear
        transport.send_envelope(build_envelope("complete"))
        File.open(transport.log_file, "a") { |file| file.write('{"timestamp":"2026-10-06T09:08:2') }

        bodies = transport.logged_envelopes.map { |envelope| envelope.dig("items", 0, "payload", "items", 0, "body") }

        expect(bodies).to eq(["complete"])
      end
    end
  end

  context "with a real DSN for testing" do
    let(:dsn) { Sentry::TestHelper::REAL_DSN }

    describe ".capture_exception with debug transport" do
      it "sends an event and logs envelope" do
        stub_request(:post, "https://getsentry.io/project/api/42/envelope/")
          .to_return(status: 200, body: "", headers: {})

        Sentry.capture_exception(error)

        expect(transport.logged_envelopes.count).to be(1)

        event = transport.logged_envelopes.last
        item = event["items"].first
        payload = item["payload"]

        expect(payload["exception"]["values"].first["value"]).to include("test error")
      end
    end
  end
end
