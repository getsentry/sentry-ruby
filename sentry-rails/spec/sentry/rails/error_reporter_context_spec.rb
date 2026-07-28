# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::ErrorReporterContext do
  describe "#execution_context", skip: Rails.version.to_f < 7.0 do
    subject(:context) do
      Class.new { include Sentry::Rails::ErrorReporterContext }.new.execution_context["rails.error"]
    end

    before { make_basic_app }

    it "filters sensitive values the serializer expands out of an Enumerable" do
      Rails.error.set_context(records: Set[{ password: "hunter2" }])

      expect(context).to eq(records: [{ password: "[FILTERED]" }])
    end

    it "filters sensitive values nested under an Enumerable" do
      Rails.error.set_context(audit: { entries: Set[{ api_key: "secret-api-key" }] })

      expect(context).to eq(audit: { entries: [{ api_key: "[FILTERED]" }] })
    end

    it "still passes non-enumerable values through the serializer untouched" do
      Rails.error.set_context(
        debug_key: "important_value",
        timestamp: Time.utc(2026, 7, 21, 12, 34, 56),
        date: Date.new(2026, 7, 21)
      )

      expect(context).to include(
        debug_key: "important_value",
        timestamp: Time.utc(2026, 7, 21, 12, 34, 56),
        date: Date.new(2026, 7, 21)
      )
    end
  end
end
