module Sentry
  class Transaction < Span
    SENTRY_TRACE_REGEXP = Regexp.new(
      "^[ \t]*" +  # whitespace
      "([0-9a-f]{32})?" +  # trace_id
      "-?([0-9a-f]{16})?" +  # span_id
      "-?([01])?" +  # sampled
      "[ \t]*$"  # whitespace
    )
    UNLABELD_NAME = "<unlabeled transaction>".freeze

    attr_reader :name, :parent_sampled

    def initialize(name: nil, parent_sampled: nil, **options)
      super(**options)

      @name = name
      @parent_sampled = parent_sampled
    end

    def self.from_sentry_trace(sentry_trace, **options)
      return unless sentry_trace

      match = SENTRY_TRACE_REGEXP.match(sentry_trace)
      trace_id, parent_span_id, sampled_flag = match[1..3]

      sampled = sampled_flag != "0"

      new(trace_id: trace_id, parent_span_id: parent_span_id, parent_sampled: sampled, **options)
    end

    def to_hash
      hash = super
      hash.merge!(name: @name, sampled: @sampled, parent_sampled: @parent_sampled)
      hash
    end

    def finish(hub: nil)
      super() # Span#finish doesn't take arguments

      if @name.nil?
        @name = UNLABELD_NAME
      end

      return unless @sampled

      hub ||= Sentry.get_current_hub
      event = hub.current_client.event_from_transaction(self)
      hub.capture_event(event)
    end
  end
end
