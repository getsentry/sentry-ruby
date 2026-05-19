# frozen_string_literal: true

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

  describe "event leakage across clone_hub_to_current_thread (regression for #2951)" do
    it "keeps sentry_events empty after setup_sentry_test even when an earlier request captured events through a cloned hub" do
      setup_sentry_test
      Sentry.capture_message("event from a previous test")
      teardown_sentry_test

      Sentry.clone_hub_to_current_thread
      Sentry.capture_message("event from an unrelated request")

      setup_sentry_test

      expect(sentry_events).to be_empty

      Sentry.clone_hub_to_current_thread

      expect(sentry_events).to be_empty

      teardown_sentry_test
    end
  end

  describe "request-captured events remain observable after clone_hub_to_current_thread" do
    after { teardown_sentry_test }

    it "still exposes events captured through a hub the Rack middleware cloned after setup_sentry_test" do
      setup_sentry_test

      Sentry.clone_hub_to_current_thread
      Sentry.capture_message("event from the request")

      expect(sentry_events.map(&:message)).to include("event from the request")
    end
  end

  describe "Sentry::Rack::CaptureExceptions across consecutive requests (regression for #2951)", when: :rack_available? do
    # Drives a single request through the real Rack middleware. The middleware
    # calls Sentry.clone_hub_to_current_thread before handing off to the app,
    # exactly like a Rails request spec would.
    def perform_request(exception_message)
      exception = RuntimeError.new(exception_message)
      app = lambda do |env|
        env["rack.exception"] = exception
        [200, {}, ["ok"]]
      end
      stack = Sentry::Rack::CaptureExceptions.new(app)
      stack.call(Rack::MockRequest.env_for("/#{exception_message}"))
    end

    def captured_exception_messages
      sentry_events.map { |event| event.to_h.dig(:exception, :values, 0, :value) }
    end

    it "isolates each request's events and keeps them observable via sentry_events" do
      # First request, wrapped in the test helper just like a request spec.
      setup_sentry_test
      perform_request("first-request")
      messages = captured_exception_messages
      expect(messages.size).to eq(1)
      expect(messages.first).to include("first-request")
      teardown_sentry_test

      # Second request: a fresh setup must not see the first request's event,
      # even though the Rack middleware clones the main hub on every request.
      setup_sentry_test
      expect(sentry_events).to be_empty

      perform_request("second-request")
      messages = captured_exception_messages
      expect(messages.size).to eq(1)
      expect(messages.first).to include("second-request")
      expect(messages).not_to include(a_string_including("first-request"))

      teardown_sentry_test
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

    it "clears global processors" do
      Sentry.add_global_event_processor { |event| event }
      teardown_sentry_test
      expect(Sentry::Scope.global_event_processors).to eq([])
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
