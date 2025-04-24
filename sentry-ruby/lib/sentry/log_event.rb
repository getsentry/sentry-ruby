# frozen_string_literal: true

module Sentry
  class LogEvent < Event
    TYPE = "log"

    LEVELS = %i[trace debug info warn error fatal].freeze

    attr_accessor :level, :body, :attributes, :trace_id

    def initialize(configuration: Sentry.configuration, **options)
      super(configuration: configuration)
      @type = TYPE
      @level = options.fetch(:level)
      @body = options[:body]
      @trace_id = options[:trace_id] || SecureRandom.hex(16)
      @attributes = options[:attributes] || {}
    end

    # https://develop.sentry.dev/sdk/telemetry/logs/#log-envelope-item-payload
    def to_hash
      data = {}
      data[:level] = @level.to_s
      data[:body] = @body
      data[:timestamp] = Time.parse(@timestamp).to_f
      data[:trace_id] = @trace_id
      data[:attributes] = serialize_attributes
      data
    end

    private

    def serialize_attributes
      result = {}

      @attributes.each do |key, value|
        result[key.to_s] = {
          value: value.to_s,
          type: value_type(value)
        }
      end

      result
    end

    def value_type(value)
      case value
      when Integer
        "integer"
      when TrueClass, FalseClass
        "boolean"
      when Float
        "double"
      else
        "string"
      end
    end
  end
end
