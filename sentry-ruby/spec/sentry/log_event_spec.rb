# frozen_string_literal: true

RSpec.describe Sentry::LogEvent do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = Sentry::TestHelper::DUMMY_DSN
    end
  end

  describe "#initialize" do
    it "initializes with required attributes" do
      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "User John has logged in!"
      )

      expect(event).to be_a(described_class)
      expect(event.level).to eq(:info)
      expect(event.body).to eq("User John has logged in!")
    end

    it "accepts attributes" do
      attributes = {
        "sentry.message.template" => "User %s has logged in!",
        "sentry.message.parameter.0" => "John"
      }

      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "User John has logged in!",
        attributes: attributes
      )

      expect(event.attributes).to eq(attributes)
    end
  end

  describe "#to_hash" do
    before do
      configuration.release = "1.2.3"
      configuration.environment = "test"
      configuration.server_name = "server-123"
    end

    it "formats message with hash-based parameters" do
      attributes = { name: "John", day: "Monday" }

      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "Hello %{name}, today is %{day}",
        attributes: attributes
      )

      hash = event.to_hash

      expect(hash[:body]).to eq("Hello John, today is Monday")

      attributes = hash[:attributes]
      expect(attributes["sentry.message.template"]).to eq({ value: "Hello %{name}, today is %{day}", type: "string" })
      expect(attributes["sentry.message.parameter.name"]).to eq({ value: "John", type: "string" })
      expect(attributes["sentry.message.parameter.day"]).to eq({ value: "Monday", type: "string" })
    end

    it "includes all required fields" do
      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "User John has logged in!"
      )

      hash = event.to_hash

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
        configuration: configuration,
        level: :info,
        body: "User John has logged in!"
      )

      hash = event.to_hash

      expect(hash[:attributes]).not_to have_key("sentry.message.template")
    end

    it "serializes different attribute types correctly" do
      attributes = {
        "string_attr" => "string value",
        "integer_attr" => 42,
        "boolean_attr" => true,
        "float_attr" => 3.14
      }

      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "Test message",
        attributes: attributes
      )

      hash = event.to_hash

      expect(hash[:attributes]["string_attr"]).to eq({ value: "string value", type: "string" })
      expect(hash[:attributes]["integer_attr"]).to eq({ value: 42, type: "integer" })
      expect(hash[:attributes]["boolean_attr"]).to eq({ value: true, type: "boolean" })
      expect(hash[:attributes]["float_attr"]).to eq({ value: 3.14, type: "double" })
    end
  end
end
