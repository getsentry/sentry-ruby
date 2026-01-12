# frozen_string_literal: true

require "sentry/utils/telemetry_attributes"

module Sentry
  class MetricEvent
    include Sentry::Utils::TelemetryAttributes

    attr_reader :name, :type, :value, :unit, :timestamp, :trace_id, :span_id, :attributes
    attr_writer :trace_id, :span_id, :attributes

    def initialize(
      name:,
      type:,
      value:,
      unit: nil,
      attributes: nil
    )
      @name = name
      @type = type
      @value = value
      @unit = unit
      @attributes = attributes || {}

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
        timestamp: @timestamp,
        trace_id: @trace_id,
        span_id: @span_id,
        attributes: serialize_attributes
      }.compact
    end

    private

    def serialize_attributes
      @attributes.transform_values! { |v| attribute_hash(v) }
    end
  end
end
