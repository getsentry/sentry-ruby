# frozen_string_literal: true

module Sentry
  class TransactionEvent < Event
    TYPE = "transaction"

    SERIALIZEABLE_ATTRIBUTES = %i(
      event_id level timestamp start_timestamp
      release environment server_name modules
      user tags contexts extra
      transaction platform sdk type
    )

    WRITER_ATTRIBUTES = SERIALIZEABLE_ATTRIBUTES - %i(type timestamp start_timestamp level)

    attr_writer(*WRITER_ATTRIBUTES)
    attr_reader(*SERIALIZEABLE_ATTRIBUTES)

    # @return [<Array[Span]>]
    attr_accessor :spans

    # @param configuration [Configuration]
    # @param integration_meta [Hash, nil]
    # @param message [String, nil]
    def initialize(configuration:, integration_meta: nil, message: nil)
      super
      @type = TYPE
      self.level = nil
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
      data
    end
  end
end
