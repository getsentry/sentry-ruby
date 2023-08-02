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
  end
end
