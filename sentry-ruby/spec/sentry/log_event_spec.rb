# frozen_string_literal: true

RSpec.describe Sentry::LogEvent do
  before do
    perform_basic_setup do |config|
      config.environment = "test"
      config.release = "1.2.3"
      config.server_name = "server-123"
    end
  end

  let(:event_with_applied_scope_with_user) do
    scope = Sentry::Scope.new
    scope.set_user({ id: 123, username: "john_doe", email: "john@example.com" })

    event = described_class.new(level: :info, body: "User John has logged in!")
    scope.apply_to_telemetry(event)
    event
  end

  describe "#initialize" do
    it "initializes with required attributes" do
      event = described_class.new(
        level: :info,
        body: "User John has logged in!"
      )

      expect(event).to be_a(described_class)
      expect(event.level).to eq(:info)
      expect(event.body).to eq("User John has logged in!")
    end

    it "accepts origin parameter" do
      event = described_class.new(
        level: :info,
        body: "Database query executed",
        origin: "auto.db.rails"
      )

      expect(event.origin).to eq("auto.db.rails")
    end

    it "accepts attributes" do
      attributes = {
        "sentry.message.template" => "User %s has logged in!",
        "sentry.message.parameter.0" => "John"
      }

      event = described_class.new(
        level: :info,
        body: "User John has logged in!",
        attributes: attributes
      )

      expect(event.attributes).to eq(attributes)
    end
  end

  describe "#to_h" do
    it "formats message with hash-based parameters" do
      attributes = { name: "John", day: "Monday" }

      event = described_class.new(
        level: :info,
        body: "Hello %{name}, today is %{day}",
        attributes: attributes
      )

      hash = event.to_h

      expect(hash[:body]).to eq("Hello John, today is Monday")

      attributes = hash[:attributes]
      expect(attributes["sentry.message.template"]).to eq({ value: "Hello %{name}, today is %{day}", type: "string" })
      expect(attributes["sentry.message.parameter.name"]).to eq({ value: "John", type: "string" })
      expect(attributes["sentry.message.parameter.day"]).to eq({ value: "Monday", type: "string" })
    end

    it "includes all required fields" do
      hash = event_with_applied_scope_with_user.to_h

      expect(hash[:level]).to eq("info")
      expect(hash[:body]).to eq("User John has logged in!")
      expect(hash[:timestamp]).to be_a(Float)

      attributes = hash[:attributes]

      expect(attributes).to be_a(Hash)
      expect(attributes["sentry.sdk.name"]).to eq({ value: "sentry.ruby", type: "string" })
      expect(attributes["sentry.sdk.version"]).to eq({ value: Sentry::VERSION, type: "string" })
    end

    it "doesn't set message.template when the body is not a template" do
      event = described_class.new(
        level: :info,
        body: "User John has logged in!"
      )

      hash = event.to_h

      expect(hash[:attributes]).not_to have_key("sentry.message.template")
    end

    it "doesn't set message.template when template has no parameters" do
      event = described_class.new(
        level: :info,
        body: "Hello %{name}, today is %{day}"
      )

      hash = event.to_h

      expect(hash[:attributes]).not_to have_key("sentry.message.template")
      expect(hash[:attributes]).not_to have_key("sentry.message.parameter.name")
      expect(hash[:attributes]).not_to have_key("sentry.message.parameter.day")
    end

    it "sets message.template only when parameters are present" do
      attributes = {
        "sentry.message.parameter.0" => "John"
      }

      event = described_class.new(
        level: :info,
        body: "User %s has logged in!",
        attributes: attributes
      )

      hash = event.to_h

      expect(hash[:attributes]).to have_key("sentry.message.template")
      expect(hash[:attributes]["sentry.message.template"]).to eq({ value: "User %s has logged in!", type: "string" })
      expect(hash[:attributes]["sentry.message.parameter.0"]).to eq({ value: "John", type: "string" })
    end

    it "serializes different attribute types correctly" do
      attributes = {
        "string_attr" => "string value",
        "integer_attr" => 42,
        "boolean_attr" => true,
        "float_attr" => 3.14
      }

      event = described_class.new(
        level: :info,
        body: "Test message",
        attributes: attributes
      )

      hash = event.to_h

      expect(hash[:attributes]["string_attr"]).to eq({ value: "string value", type: "string" })
      expect(hash[:attributes]["integer_attr"]).to eq({ value: 42, type: "integer" })
      expect(hash[:attributes]["boolean_attr"]).to eq({ value: true, type: "boolean" })
      expect(hash[:attributes]["float_attr"]).to eq({ value: 3.14, type: "double" })
    end

    it "serializes user attributes correctly" do
      # Enable send_default_pii so user attributes are added
      Sentry.configuration.send_default_pii = true
      hash = event_with_applied_scope_with_user.to_h

      # User attributes are now wrapped with type information (consistent with MetricEvent)
      expect(hash[:attributes]["user.id"]).to eq({ value: 123, type: "integer" })
      expect(hash[:attributes]["user.name"]).to eq({ value: "john_doe", type: "string" })
      expect(hash[:attributes]["user.email"]).to eq({ value: "john@example.com", type: "string" })
    end

    it "includes sentry.origin attribute when origin is set" do
      event = described_class.new(
        level: :info,
        body: "Database query executed",
        origin: "auto.db.rails"
      )

      hash = event.to_h

      expect(hash[:attributes]["sentry.origin"]).to eq({ value: "auto.db.rails", type: "string" })
    end

    it "does not include sentry.origin attribute when origin is nil" do
      event = described_class.new(
        level: :info,
        body: "Manual log message"
      )

      hash = event.to_h

      expect(hash[:attributes]).not_to have_key("sentry.origin")
    end
  end
end
