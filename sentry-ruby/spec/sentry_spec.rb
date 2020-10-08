RSpec.describe Sentry do
  def setup_current_hub
    Sentry.init do |config|
      config.scheme = "dummy"
      config.tags = { foo: "bar" }
    end
  end

  let(:event) do
    Sentry::Event.new(configuration: Sentry::Configuration.new, options: Sentry::Event::Options.new)
  end

  describe ".init" do
    it "initializes the current hub" do
      described_class.init do |config|
        config.scheme = "dummy"
        config.tags = { foo: "bar" }
      end

      current_hub = described_class.get_current_hub
      expect(current_hub).to be_a(Sentry::Hub)
      expect(current_hub.current_scope).to be_a(Sentry::Scope)
      expect(current_hub.current_client.configuration.tags).to eq({ foo: "bar" })
    end
  end

  describe ".configure_scope" do
    before do
      setup_current_hub
    end

    it "yields the current hub's scope" do
      scope = nil
      described_class.configure_scope { |s| scope = s }

      expect(scope).to eq(described_class.get_current_hub.current_scope)
    end
  end

  describe ".capture_event" do
    before do
      setup_current_hub
    end

    it "sends the event via current hub" do
      expect(described_class.get_current_hub).to receive(:capture_event).with(event)

      described_class.capture_event(event)
    end
  end

  describe ".capture_exception" do
    let(:exception) { ZeroDivisionError.new("divided by 0") }

    before do
      setup_current_hub
    end

    it "sends the message via current hub" do
      expect(described_class.get_current_hub).to receive(:capture_exception).with(exception, tags: { foo: "baz" })

      described_class.capture_exception(exception, tags: { foo: "baz" })
    end
  end

  describe ".capture_message" do
    before do
      setup_current_hub
    end

    it "sends the message via current hub" do
      expect(described_class.get_current_hub).to receive(:capture_message).with("Test", tags: { foo: "baz" })

      described_class.capture_message("Test", tags: { foo: "baz" })
    end
  end

  describe ".last_event_id" do
    before do
      setup_current_hub
    end

    it "gets the last_event_id from current_hub" do
      expect(described_class.get_current_hub).to receive(:last_event_id)

      described_class.last_event_id
    end
  end
end
