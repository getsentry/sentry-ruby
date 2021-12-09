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

    attr_accessor :spans

    def initialize(configuration:, integration_meta: nil, message: nil)
      super
      @type = TYPE
    end

    def start_timestamp=(time)
      @start_timestamp = time.is_a?(Time) ? time.to_f : time
    end

    def to_hash
      data = super
      data[:spans] = @spans.map(&:to_hash) if @spans
      data
    end
  end
end
