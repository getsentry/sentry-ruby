# frozen_string_literal: true

module Sentry
  class TransactionEvent < Event
    ATTRIBUTES = %i(
      event_id level timestamp start_timestamp
      release environment server_name modules
      user tags contexts extra
      transaction platform sdk type
    )

    attr_accessor(*ATTRIBUTES)
    attr_accessor :spans

    def start_timestamp=(time)
      @start_timestamp = time.is_a?(Time) ? time.strftime('%Y-%m-%dT%H:%M:%S') : time
    end

    def type
      "transaction"
    end

    def to_hash
      data = super
      data[:spans] = @spans.map(&:to_hash) if @spans
      data
    end
  end
end
