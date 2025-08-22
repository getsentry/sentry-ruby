# frozen_string_literal: true

require "securerandom"
require "sentry/baggage"
require "sentry/utils/uuid"
require "sentry/utils/sample_rand"

module Sentry
  class PropagationContext
    SENTRY_TRACE_REGEXP = Regexp.new(
      "\\A([0-9a-f]{32})?" + # trace_id
      "-?([0-9a-f]{16})?" +  # span_id
      "-?([01])?\\z"         # sampled
    )

    # An uuid that can be used to identify a trace.
    # @return [String]
    attr_reader :trace_id
    # An uuid that can be used to identify the span.
    # @return [String]
    attr_reader :span_id
    # Span parent's span_id.
    # @return [String, nil]
    attr_reader :parent_span_id
    # The sampling decision of the parent transaction.
    # @return [Boolean, nil]
    attr_reader :parent_sampled
    # Is there an incoming trace or not?
    # @return [Boolean]
    attr_reader :incoming_trace
    # This is only for accessing the current baggage variable.
    # Please use the #get_baggage method for interfacing outside this class.
    # @return [Baggage, nil]
    attr_reader :baggage
    # The propagated random value used for sampling decisions.
    # @return [Float, nil]
    attr_reader :sample_rand

    # Extract the trace_id, parent_span_id and parent_sampled values from a sentry-trace header.
    #
    # @param sentry_trace [String] the sentry-trace header value from the previous transaction.
    # @return [Array, nil]
    def self.extract_sentry_trace(sentry_trace)
      value = sentry_trace.to_s.strip
      return if value.empty?

      match = SENTRY_TRACE_REGEXP.match(value)
      return if match.nil?

      trace_id, parent_span_id, sampled_flag = match[1..3]
      parent_sampled = sampled_flag.nil? ? nil : sampled_flag != "0"

      [trace_id, parent_span_id, parent_sampled]
    end

    def self.extract_sample_rand_from_baggage(baggage, trace_id = nil)
      return unless baggage&.items

      sample_rand_str = baggage.items["sample_rand"]
      return unless sample_rand_str

      generator = Utils::SampleRand.new(trace_id: trace_id)
      generator.generate_from_value(sample_rand_str)
    end

    def self.generate_sample_rand(baggage, trace_id, parent_sampled)
      generator = Utils::SampleRand.new(trace_id: trace_id)

      if baggage&.items && !parent_sampled.nil?
        sample_rate_str = baggage.items["sample_rate"]
        sample_rate = sample_rate_str&.to_f

        if sample_rate && !parent_sampled.nil?
          generator.generate_from_sampling_decision(parent_sampled, sample_rate)
        else
          generator.generate_from_trace_id
        end
      else
        generator.generate_from_trace_id
      end
    end

    def initialize(scope, env = nil)
      @scope = scope
      @parent_span_id = nil
      @parent_sampled = nil
      @baggage = nil
      @incoming_trace = false
      @sample_rand = nil

      if env
        sentry_trace_header = env["HTTP_SENTRY_TRACE"] || env[SENTRY_TRACE_HEADER_NAME]
        baggage_header = env["HTTP_BAGGAGE"] || env[BAGGAGE_HEADER_NAME]

        if sentry_trace_header
          sentry_trace_data = self.class.extract_sentry_trace(sentry_trace_header)

          if sentry_trace_data
            @trace_id, @parent_span_id, @parent_sampled = sentry_trace_data

            @baggage =
              if baggage_header && !baggage_header.empty?
                Baggage.from_incoming_header(baggage_header)
              else
                # If there's an incoming sentry-trace but no incoming baggage header,
                # for instance in traces coming from older SDKs,
                # baggage will be empty and frozen and won't be populated as head SDK.
                Baggage.new({})
              end

            @sample_rand = self.class.extract_sample_rand_from_baggage(@baggage, @trace_id)

            @baggage.freeze!
            @incoming_trace = true
          end
        end
      end

      @trace_id ||= Utils.uuid
      @span_id = Utils.uuid.slice(0, 16)
      @sample_rand ||= self.class.generate_sample_rand(@baggage, @trace_id, @parent_sampled)
    end

    # Returns the trace context that can be used to embed in an Event.
    # @return [Hash]
    def get_trace_context
      {
        trace_id: trace_id,
        span_id: span_id,
        parent_span_id: parent_span_id
      }
    end

    # Returns the sentry-trace header from the propagation context.
    # @return [String]
    def get_traceparent
      "#{trace_id}-#{span_id}"
    end

    # Returns the Baggage from the propagation context or populates as head SDK if empty.
    # @return [Baggage, nil]
    def get_baggage
      populate_head_baggage if @baggage.nil? || @baggage.mutable
      @baggage
    end

    # Returns the Dynamic Sampling Context from the baggage.
    # @return [Hash, nil]
    def get_dynamic_sampling_context
      get_baggage&.dynamic_sampling_context
    end

    private

    def populate_head_baggage
      return unless Sentry.initialized?

      configuration = Sentry.configuration

      items = {
        "trace_id" => trace_id,
        "sample_rand" => Utils::SampleRand.format(@sample_rand),
        "environment" => configuration.environment,
        "release" => configuration.release,
        "public_key" => configuration.dsn&.public_key
      }

      items.compact!
      @baggage = Baggage.new(items, mutable: false)
    end
  end
end
