# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::MetricEvent do
  let(:metric_event) do
    described_class.new(
      name: "test.metric",
      type: :distribution,
      value: 5.0,
      unit: 'seconds',
    )
  end

  before do
    perform_basic_setup do |config|
      config.environment = "test"
      config.release = "1.0.0"
      config.server_name = "test-server"
    end
  end

  describe "#initialize" do
    it "initializes with required parameters" do
      expect(metric_event.name).to eq("test.metric")
      expect(metric_event.type).to eq(:distribution)
      expect(metric_event.value).to eq(5.0)
      expect(metric_event.unit).to eq('seconds')
      expect(metric_event.attributes).to eq({})

      expect(metric_event.timestamp).to be_a(Time)
      expect(metric_event.trace_id).to be_nil
      expect(metric_event.span_id).to be_nil
      expect(metric_event.user).to eq({})
    end

    it "accepts custom attributes" do
      event = described_class.new(
        name: "test.metric_attributes",
        type: :counter,
        value: 1,
        attributes: { "foo" => "bar" }
      )

      expect(event.attributes).to eq({ "foo" => "bar" })
    end
  end

  describe "#to_h" do
    it "returns a hash with basic metric data" do
      hash = metric_event.to_h
      expect(hash[:name]).to eq("test.metric")
      expect(hash[:type]).to eq(:distribution)
      expect(hash[:value]).to eq(5.0)
      expect(hash[:unit]).to eq("seconds")
      expect(hash[:timestamp]).to be_a(Time)
    end

    it "includes trace info if provided" do
      metric_event.trace_id = "000"
      metric_event.span_id = "00"
      hash = metric_event.to_h

      expect(hash[:trace_id]).to eq("000")
      expect(hash[:span_id]).to eq("00")
    end

    it "excludes trace info if not provided (compact)" do
      hash = metric_event.to_h

      expect(hash.key?(:trace_id)).to eq(false)
      expect(hash.key?(:span_id)).to eq(false)
    end

    it "includes default attributes from configuration" do
      hash = metric_event.to_h
      attributes = hash[:attributes]

      expect(attributes["sentry.environment"]).to eq({ type: "string", value: "test" })
      expect(attributes["sentry.release"]).to eq({ type: "string", value: "1.0.0" })
      expect(attributes["sentry.sdk.name"]).to eq({ type: "string", value: Sentry.sdk_meta["name"] })
      expect(attributes["sentry.sdk.version"]).to eq({ type: "string", value: Sentry.sdk_meta["version"] })
      expect(attributes["server.address"]).to eq({ type: "string", value: "test-server" })
    end

    it "includes custom attributes with inferred types" do
      event = described_class.new(
        name: "test.metric",
        type: "counter",
        value: 1.0,
        attributes: {
          "str" => "foo",
          "float" => 1.23,
          "int" => 99,
          "bool_t" => true,
          "bool_f" => false,
          "unknown" =>  Object.new
        }
      )

      hash = event.to_h
      attributes = hash[:attributes]

      expect(attributes["str"]).to eq({ type: "string", value: "foo" })
      expect(attributes["float"]).to eq({ type: "double", value: 1.23 })
      expect(attributes["int"]).to eq({ type: "integer", value: 99 })
      expect(attributes["bool_t"]).to eq({ type: "boolean", value: true })
      expect(attributes["bool_f"]).to eq({ type: "boolean", value: false })

      expect(attributes["unknown"][:type]).to eq("string")
      expect(attributes["unknown"][:value]).to include("Object")
    end

    it "merges custom attributes with default attributes" do
      event = described_class.new(
        name: "test.metric",
        type: "counter",
        value: 1.0,
        attributes: { "custom" => "value" }
      )
      hash = event.to_h
      attributes = hash[:attributes]

      expect(attributes["sentry.environment"]).to eq({ type: "string", value: "test" })
      expect(attributes["custom"]).to eq({ type: "string", value: "value" })
    end

    context "with user data" do
      before do
        metric_event.user = { id: "123", username: "jane", email: "jane.doe@email.com" }
      end

      context "when send_default_pii is true" do
        before do
          Sentry.configuration.send_default_pii = true
        end

        it "includes user.id attribute" do
          hash = metric_event.to_h

          expect(hash[:attributes]["user.id"]).to eq({ type: "string", value: "123" })
          expect(hash[:attributes]["user.name"]).to eq({ type: "string", value: "jane" })
          expect(hash[:attributes]["user.email"]).to eq({ type: "string", value: "jane.doe@email.com" })
        end
      end

      context "when send_default_pii is false" do
        before do
          Sentry.configuration.send_default_pii = false
        end

        it "does not include user attributes" do
          hash = metric_event.to_h

          expect(hash[:attributes].key?("user.id")).to eq(false)
          expect(hash[:attributes].key?("user.name")).to eq(false)
          expect(hash[:attributes].key?("user.email")).to eq(false)
        end
      end
    end
  end
end
