require "spec_helper"

RSpec.describe Sentry::TestHelper do
  include described_class

  before do
    # simulate normal user setup
    Sentry.init do |config|
      config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
      config.enabled_environments = ["production"]
      config.environment = :test
    end

    expect(Sentry.configuration.dsn.to_s).to eq('https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472')
    expect(Sentry.configuration.enabled_environments).to eq(["production"])
    expect(Sentry.get_current_client.transport).to be_a(Sentry::HTTPTransport)
  end

  describe "#setup_sentry_test" do
    after do
      teardown_sentry_test
    end

    it "raises error when the SDK is not initialized" do
      allow(Sentry).to receive(:initialized?).and_return(false)

      expect do
        setup_sentry_test
      end.to raise_error(RuntimeError)
    end

    it "overrides DSN, enabled_environments and transport for testing" do
      setup_sentry_test

      expect(Sentry.configuration.dsn.to_s).to eq(Sentry::TestHelper::DUMMY_DSN)
      expect(Sentry.configuration.enabled_environments).to eq(["production", "test"])
      expect(Sentry.get_current_client.transport).to be_a(Sentry::DummyTransport)
    end

    it "takes block argument for further customization" do
      setup_sentry_test do |config|
        config.traces_sample_rate = 1.0
      end

      expect(Sentry.configuration.traces_sample_rate).to eq(1.0)
    end
  end

  describe "#last_sentry_event" do
    before do
      setup_sentry_test
    end

    after do
      teardown_sentry_test
    end

    it "returns the last sent event" do
      Sentry.capture_message("foobar")
      Sentry.capture_message("barbaz")

      event = last_sentry_event

      expect(event.message).to eq("barbaz")
    end
  end

  describe "#extract_sentry_exceptions" do
    before do
      setup_sentry_test
    end

    after do
      teardown_sentry_test
    end

    it "extracts exceptions from an ErrorEvent" do
      event = Sentry.get_current_client.event_from_exception(Exception.new("foobar"))

      exceptions = extract_sentry_exceptions(event)

      expect(exceptions.count).to eq(1)
      expect(exceptions.first.type).to eq("Exception")
    end

    it "returns an empty array when there's no exceptions" do
      event = Sentry.get_current_client.event_from_message("foo")

      exceptions = extract_sentry_exceptions(event)

      expect(exceptions.count).to eq(0)
    end
  end

  describe "#teardown_sentry_test" do
    before do
      setup_sentry_test
    end

    it "clears stored events" do
      Sentry.capture_message("foobar")

      expect(sentry_events.count).to eq(1)

      teardown_sentry_test

      expect(sentry_events.count).to eq(0)
    end

    it "clears stored envelopes" do
      event = Sentry.get_current_client.event_from_message("foobar")
      envelope = sentry_transport.envelope_from_event(event)
      sentry_transport.send_envelope(envelope)

      expect(sentry_envelopes.count).to eq(1)

      teardown_sentry_test

      expect(sentry_envelopes.count).to eq(0)
    end

    it "clears the scope" do
      Sentry.set_tags(foo: "bar")

      teardown_sentry_test

      expect(Sentry.get_current_scope.tags).to eq({})
    end

    context "when the configuration is mutated" do
      it "rolls back client changes" do
        Sentry.configuration.environment = "quack"
        expect(Sentry.configuration.environment).to eq("quack")

        teardown_sentry_test

        expect(Sentry.configuration.environment).to eq("test")
      end
    end
  end
end
