# frozen_string_literal: true

module Sentry
  # Event type that represents a log entry with its attributes
  #
  # @see https://develop.sentry.dev/sdk/telemetry/logs/#log-envelope-item-payload
  class LogEvent < Event
    TYPE = "log"

    SERIALIZEABLE_ATTRIBUTES = %i[
      level
      body
      timestamp
      trace_id
      attributes
      release
      sdk
      platform
      environment
      server_name
      trace_id
    ]

    SENTRY_ATTRIBUTES = {
      "sentry.trace.parent_span_id" => :parent_span_id
    }

    LEVELS = %i[trace debug info warn error fatal].freeze

    attr_accessor :level, :body, :attributes, :trace_id

    def initialize(configuration: Sentry.configuration, **options)
      super(configuration: configuration)
      @type = TYPE
      @level = options.fetch(:level)
      @body = options[:body]
      @attributes = options[:attributes] || {}
      @contexts = {}
    end

    def to_hash
      SERIALIZEABLE_ATTRIBUTES.each_with_object({}) do |name, memo|
        memo[name] = serialize(name)
      end
    end

    private

    def serialize(name)
      serializer = :"serialize_#{name}"

      if respond_to?(serializer, true)
        __send__(serializer)
      else
        public_send(name)
      end
    end

    def serialize_level
      level.to_s
    end

    def serialize_timestamp
      Time.parse(timestamp).to_f
    end

    def serialize_trace_id
      @contexts.dig(:trace, :trace_id)
    end

    def serialize_parent_span_id
      @contexts.dig(:trace, :parent_span_id)
    end

    def serialize_attributes
      hash = @attributes.each_with_object({}) do |(key, value), memo|
        memo[key] = {
          value: value,
          type: value_type(value)
        }
      end

      SENTRY_ATTRIBUTES.each do |key, name|
        if (value = serialize(name))
          hash[key] = value
        end
      end

      hash
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
