# frozen_string_literal: true

module Sentry
  # Event type that represents a log entry with its attributes
  #
  # @see https://develop.sentry.dev/sdk/telemetry/logs/#log-envelope-item-payload
  class LogEvent < Event
    TYPE = "log"

    DEFAULT_PARAMETERS = [].freeze
    DEFAULT_ATTRIBUTES = {}.freeze
    DEFAULT_CONTEXT = {}.freeze

    SERIALIZEABLE_ATTRIBUTES = %i[
      level
      body
      timestamp
      trace_id
      attributes
    ]

    SENTRY_ATTRIBUTES = {
      "sentry.trace.parent_span_id" => :parent_span_id,
      "sentry.environment" => :environment,
      "sentry.release" => :release,
      "sentry.address" => :server_name,
      "sentry.sdk.name" => :sdk_name,
      "sentry.sdk.version" => :sdk_version,
      "sentry.message.template" => :template
    }

    LEVELS = %i[trace debug info warn error fatal].freeze

    attr_accessor :level, :body, :template, :attributes

    def initialize(configuration: Sentry.configuration, **options)
      super(configuration: configuration)

      @type = TYPE
      @level = options.fetch(:level)
      @body = options[:body]
      @template = @body if is_template?
      @attributes = options[:attributes] || DEFAULT_ATTRIBUTES
      @contexts = DEFAULT_CONTEXT
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

    def serialize_sdk_name
      Sentry.sdk_meta["name"]
    end

    def serialize_sdk_version
      Sentry.sdk_meta["version"]
    end

    def serialize_timestamp
      Time.parse(timestamp).to_f
    end

    def serialize_trace_id
      contexts.dig(:trace, :trace_id)
    end

    def serialize_parent_span_id
      contexts.dig(:trace, :parent_span_id)
    end

    def serialize_body
      if parameters.empty?
        body
      elsif parameters.is_a?(Hash)
        body % parameters
      else
        sprintf(body, *parameters)
      end
    end

    def serialize_attributes
      hash = attributes.each_with_object({}) do |(key, value), memo|
        memo[key] = attribute_hash(value)
      end

      SENTRY_ATTRIBUTES.each do |key, name|
        if (value = serialize(name))
          hash[key] = attribute_hash(value)
        end
      end

      hash
    end

    def attribute_hash(value)
      { value: value, type: value_type(value) }
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

    def parameters
      @parameters ||= begin
        return DEFAULT_PARAMETERS unless template

        parameters = template_tokens.empty? ?
          attributes.fetch(:parameters, DEFAULT_PARAMETERS) : attributes.slice(*template_tokens)

        if parameters.is_a?(Hash)
          parameters.each do |key, value|
            attributes["sentry.message.parameter.#{key}"] = value
          end
        else
          parameters.each_with_index do |param, index|
            attributes["sentry.message.parameter.#{index}"] = param
          end
        end
      end
    end

    TOKEN_REGEXP = /%\{(\w+)\}/

    def template_tokens
      @template_tokens ||= body.scan(TOKEN_REGEXP).flatten.map(&:to_sym)
    end

    def is_template?
      body.include?("%s") || TOKEN_REGEXP.match?(body)
    end
  end
end
