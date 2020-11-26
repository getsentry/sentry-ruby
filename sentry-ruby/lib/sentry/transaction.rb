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
    MESSAGE_PREFIX = "[Tracing]"

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

    def set_initial_sample_desicion(sampling_context = {})
      unless Sentry.configuration.tracing_enabled?
        @sampled = false
        return
      end

      return unless @sampled.nil?

      transaction_description = generate_transaction_description

      logger = Sentry.configuration.logger
      sample_rate = Sentry.configuration.traces_sample_rate
      traces_sampler = Sentry.configuration.traces_sampler

      if traces_sampler.is_a?(Proc)
        sampling_context = sampling_context.merge(
          parent_sampled: @parent_sampled,
          transaction_context: self.to_hash
        )

        sample_rate = traces_sampler.call(sampling_context)
      end

      unless [true, false].include?(sample_rate) || (sample_rate.is_a?(Float) && sample_rate >= 0.0 && sample_rate <= 1.0)
        @sampled = false
        logger.warn("#{MESSAGE_PREFIX} Discarding #{transaction_description} because of invalid sample_rate: #{sample_rate}")
        return
      end

      if sample_rate == 0.0 || sample_rate == false
        @sampled = false
        logger.debug("#{MESSAGE_PREFIX} Discarding #{transaction_description} because traces_sampler returned 0 or false")
        return
      end

      if sample_rate == true
        @sampled = true
      else
        @sampled = Random.rand < sample_rate
      end

      if @sampled
        logger.debug("#{MESSAGE_PREFIX} Starting #{transaction_description}")
      else
        logger.debug(
          "#{MESSAGE_PREFIX} Discarding #{transaction_description} because it's not included in the random sample (sampling rate = #{sample_rate})"
        )
      end
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

    private

    def generate_transaction_description
      result = op.nil? ? "" : "<#{@op}> "
      result += "transaction"
      result += " <#{@name}>" if @name
      result
    end
  end
end
