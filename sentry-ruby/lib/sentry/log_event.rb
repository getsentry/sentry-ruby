# frozen_string_literal: true

require "sentry/utils/telemetry_attributes"

module Sentry
  # Event type that represents a log entry with its attributes
  #
  # @see https://develop.sentry.dev/sdk/telemetry/logs/#log-envelope-item-payload
  class LogEvent
    include Sentry::Utils::TelemetryAttributes

    TYPE = "log"

    DEFAULT_PARAMETERS = [].freeze

    PARAMETER_PREFIX = "sentry.message.parameter"

    LEVELS = %i[trace debug info warn error fatal].freeze

    attr_accessor :level, :body, :template, :attributes, :origin, :trace_id, :span_id
    attr_reader :timestamp

    TOKEN_REGEXP = /%\{(\w+)\}/

    def initialize(**options)
      @type = TYPE
      @timestamp = Sentry.utc_now
      @level = options.fetch(:level)
      @body = options[:body]
      @template = @body if is_template?
      @attributes = options[:attributes] || {}
      @origin = options[:origin]
      @trace_id = nil
      @span_id = nil
    end

    def to_h
      {
        level: level.to_s,
        timestamp: timestamp.to_f,
        trace_id: @trace_id,
        span_id: @span_id,
        body: serialize_body,
        attributes: serialize_attributes
      }.compact
    end

    private

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
      populate_sentry_attributes!
      @attributes.transform_values! { |v| attribute_hash(v) }
    end

    def populate_sentry_attributes!
      @attributes["sentry.origin"] ||= @origin if @origin
      @attributes["sentry.message.template"] ||= template if has_parameters?
    end

    def parameters
      @parameters ||= begin
        return DEFAULT_PARAMETERS unless template

        parameters = template_tokens.empty? ?
          attributes.fetch(:parameters, DEFAULT_PARAMETERS) : attributes.slice(*template_tokens)

        if parameters.is_a?(Hash)
          parameters.each do |key, value|
            attributes["#{PARAMETER_PREFIX}.#{key}"] = value
          end
        else
          parameters.each_with_index do |param, index|
            attributes["#{PARAMETER_PREFIX}.#{index}"] = param
          end
        end
      end
    end

    def template_tokens
      @template_tokens ||= body.scan(TOKEN_REGEXP).flatten.map(&:to_sym)
    end

    def is_template?
      body.include?("%s") || TOKEN_REGEXP.match?(body)
    end

    def has_parameters?
      attributes.keys.any? { |key| key.start_with?(PARAMETER_PREFIX) }
    end
  end
end
