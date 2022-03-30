# frozen_string_literal: true

module Sentry
  # TransactionEvent represents events that carry transaction data (type: "transaction").
  class TransactionEvent < Event
    TYPE = "transaction"

    # @return [<Array[Span]>]
    attr_accessor :spans

    # @return [Float, nil]
    attr_reader :start_timestamp

    # Sets the event's start_timestamp.
    # @param time [Time, Float]
    # @return [void]
    def start_timestamp=(time)
      @start_timestamp = time.is_a?(Time) ? time.to_f : time
    end

    # @return [Hash]
    def to_hash
      data = super
      data[:spans] = @spans.map(&:to_hash) if @spans
      data[:start_timestamp] = @start_timestamp
      data
    end
  end
end
