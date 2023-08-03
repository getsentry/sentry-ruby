# frozen_string_literal: true

require "securerandom"
require "sentry/baggage"

module Sentry
  class PropagationContext

    # An uuid that can be used to identify a trace.
    # @return [String]
    attr_reader :trace_id
    # An uuid that can be used to identify the span.
    # @return [String]
    attr_reader :span_id
    # Span parent's span_id.
    # @return [String]
    attr_reader :parent_span_id

    def initialize(scope)
      @scope = scope
      @trace_id = SecureRandom.uuid.delete("-")
      @span_id = SecureRandom.uuid.delete("-").slice(0, 16)
      @parent_span_id = nil
      @baggage = nil
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

    # Returns the W3C baggage header from the propagation context.
    # @return [String, nil]
    def get_baggage
      populate_head_baggage if @baggage.nil? || @baggage.mutable
      @baggage
    end

    # Returns the Dynamic Sampling Context from the baggage.
    # @return [String, nil]
    def get_dynamic_sampling_context
      get_baggage&.dynamic_sampling_context
    end

    private

    def populate_head_baggage
      return unless Sentry.initialized?

      configuration = Sentry.configuration

      items = {
        "trace_id" => trace_id,
        "sample_rate" => configuration.traces_sample_rate,
        "environment" => configuration.environment,
        "release" => configuration.release,
        "public_key" => configuration.dsn&.public_key
      }

      user = @scope&.user
      items["user_segment"] = user["segment"] if user && user["segment"]

      items.compact!
      @baggage = Baggage.new(items, mutable: false)
    end
  end
end
