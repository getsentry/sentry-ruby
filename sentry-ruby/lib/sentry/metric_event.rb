# frozen_string_literal: true

module Sentry
  class MetricEvent
    attr_reader :name, :type, :value, :unit, :timestamp, :trace_id, :span_id, :attributes, :user
    attr_writer :trace_id, :span_id, :attributes, :user

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
      @user = {}
    end

    def to_h
      populate_default_attributes!
      populate_user_attributes!

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

    def populate_default_attributes!
      configuration = Sentry.configuration
      return unless configuration

      default_attributes = {
        "sentry.environment" => configuration.environment,
        "sentry.release" => configuration.release,
        "sentry.sdk.name" => Sentry.sdk_meta["name"],
        "sentry.sdk.version" => Sentry.sdk_meta["version"],
        "server.address" => configuration.server_name
      }.compact

      @attributes = default_attributes.merge(@attributes)
    end

    def populate_user_attributes!
      return unless @user
      return unless Sentry.initialized? && Sentry.configuration.send_default_pii

      user_attributes = {
        "user.id" => @user[:id],
        "user.name" => @user[:username],
        "user.email" => @user[:email]
      }.compact

      @attributes = user_attributes.merge(@attributes)
    end

    def serialize_attributes
      @attributes.transform_values do |v|
        case v
        when Integer then { type: "integer", value: v }
        when Float then { type: "double", value: v }
        when TrueClass, FalseClass then { type: "boolean", value: v }
        when String then { type: "string", value: v }
        else { type: "string", value: v.to_s }
        end
      end
    end
  end
end
