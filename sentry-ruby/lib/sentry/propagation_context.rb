# frozen_string_literal: true

require "securerandom"

module Sentry
  class PropagationContext
    def initialize
      @trace_id = SecureRandom.uuid.delete("-")
      @span_id = SecureRandom.uuid.delete("-").slice(0, 16)
      @parent_span_id = nil
      @dynamic_sampling_context = nil
    end

    # Returns the trace context that can be used to embed in an Event.
    # @return [Hash]
    def get_trace_context
      {
        trace_id: @trace_id,
        span_id: @span_id,
        parent_span_id: @parent_span_id
      }
    end
  end
end
