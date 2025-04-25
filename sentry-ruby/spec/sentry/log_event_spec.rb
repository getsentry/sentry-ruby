# frozen_string_literal: true

require "spec_helper"

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
      expect(event.trace_id).to_not be(nil)
    end

    it "accepts trace_id" do
      trace_id = "5b8efff798038103d269b633813fc60c"
      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "User John has logged in!",
        trace_id: trace_id
      )

      expect(event.trace_id).to eq(trace_id)
    end

    it "accepts attributes" do
      attributes = {
        "sentry.message.template" => "User %s has logged in!",
        "sentry.message.parameters.0" => "John"
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
    it "includes all required fields" do
      trace_id = "5b8efff798038103d269b633813fc60c"
      attributes = {
        "sentry.message.template" => "User %s has logged in!",
        "sentry.message.parameters.0" => "John"
      }

      event = described_class.new(
        configuration: configuration,
        level: :info,
        body: "User John has logged in!",
        trace_id: trace_id,
        attributes: attributes
      )

      hash = event.to_hash

      expect(hash[:level]).to eq("info")
      expect(hash[:body]).to eq("User John has logged in!")
      expect(hash[:trace_id]).to eq(trace_id)
      expect(hash[:timestamp]).to be_a(Float)
      expect(hash[:attributes]).to be_a(Hash)
      expect(hash[:attributes]["sentry.message.template"]).to eq({ value: "User %s has logged in!", type: "string" })
      expect(hash[:attributes]["sentry.message.parameters.0"]).to eq({ value: "John", type: "string" })
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
