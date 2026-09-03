# frozen_string_literal: true

require "sentry/utils/telemetry_attributes"

module Sentry
  class MetricEvent
    include Sentry::Utils::TelemetryAttributes

    attr_reader :name, :type, :value, :unit, :timestamp, :trace_id, :span_id, :attributes, :sdk_meta
    attr_writer :trace_id, :span_id, :attributes

    def initialize(
      name:,
      type:,
      value:,
      unit: nil,
      attributes: nil,
      sdk_meta: nil
    )
      @name = name
      @type = type
      @value = value
      @unit = unit
      @attributes = attributes || {}
      @sdk_meta = sdk_meta || Sentry.sdk_meta

      if sdk_meta
        @attributes["sentry.sdk.name"] = sdk_meta[:name] || sdk_meta["name"]
        @attributes["sentry.sdk.version"] = sdk_meta[:version] || sdk_meta["version"]
      end

      @timestamp = Sentry.utc_now
      @trace_id = nil
      @span_id = nil
    end

    def to_h
      {
        name: @name,
        type: @type,
        value: @value,
        unit: @unit,
        timestamp: @timestamp.to_f,
        trace_id: @trace_id,
        span_id: @span_id,
        attributes: serialize_attributes
      }.compact
    end

    private

    def serialize_attributes
      @attributes.transform_values { |v| attribute_hash(v) }
    end
  end
end
