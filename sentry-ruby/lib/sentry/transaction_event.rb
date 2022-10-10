# frozen_string_literal: true

module Sentry
  # TransactionEvent represents events that carry transaction data (type: "transaction").
  class TransactionEvent < Event
    TYPE = "transaction"

    # @return [<Array[Span]>]
    attr_accessor :spans

    # @return [Hash, nil]
    attr_accessor :dynamic_sampling_context

    # @return [Float, nil]
    attr_reader :start_timestamp

    def initialize(transaction:, **options)
      super(**options)

      self.transaction = transaction.name
      self.transaction_info = { source: transaction.source }
      self.contexts.merge!(trace: transaction.get_trace_context)
      self.timestamp = transaction.timestamp
      self.start_timestamp = transaction.start_timestamp
      self.tags = transaction.tags
      self.dynamic_sampling_context = transaction.get_baggage.dynamic_sampling_context

      finished_spans = transaction.span_recorder.spans.select { |span| span.timestamp && span != transaction }
      self.spans = finished_spans.map(&:to_hash)
    end

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
