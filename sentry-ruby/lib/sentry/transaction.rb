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
      set_span_recorder
    end

    def set_span_recorder
      @span_recorder = SpanRecorder.new(1000)
      @span_recorder.add(self)
    end

    def self.from_sentry_trace(sentry_trace, configuration: Sentry.configuration, **options)
      return unless configuration.tracing_enabled?
      return unless sentry_trace

      match = SENTRY_TRACE_REGEXP.match(sentry_trace)
      return if match.nil?
      trace_id, parent_span_id, sampled_flag = match[1..3]

      parent_sampled =
        if sampled_flag.nil?
          nil
        else
          sampled_flag != "0"
        end

      new(trace_id: trace_id, parent_span_id: parent_span_id, parent_sampled: parent_sampled, **options)
    end

    def to_hash
      hash = super
      hash.merge!(name: @name, sampled: @sampled, parent_sampled: @parent_sampled)
      hash
    end

    def start_child(**options)
      child_span = super
      child_span.span_recorder = @span_recorder

      if @sampled
        @span_recorder.add(child_span)
      end

      child_span
    end

    def deep_dup
      copy = super
      copy.set_span_recorder

      @span_recorder.spans.each do |span|
        # span_recorder's first span is the current span, which should not be added to the copy's spans
        next if span == self
        copy.span_recorder.add(span.dup)
      end

      copy
    end

    def set_initial_sample_decision(sampling_context: {}, configuration: Sentry.configuration)
      unless configuration.tracing_enabled?
        @sampled = false
        return
      end

      return unless @sampled.nil?

      transaction_description = generate_transaction_description

      logger = configuration.logger
      traces_sampler = configuration.traces_sampler

      sample_rate =
        if traces_sampler.is_a?(Proc)
          sampling_context = sampling_context.merge(
            parent_sampled: @parent_sampled,
            transaction_context: self.to_hash
          )

          traces_sampler.call(sampling_context)
        elsif !@parent_sampled.nil?
          @parent_sampled
        else
          configuration.traces_sample_rate
        end

      unless [true, false].include?(sample_rate) || (sample_rate.is_a?(Numeric) && sample_rate >= 0.0 && sample_rate <= 1.0)
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

      return unless @sampled || @parent_sampled

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

    class SpanRecorder
      attr_reader :max_length, :spans

      def initialize(max_length)
        @max_length = max_length
        @spans = []
      end

      def add(span)
        if @spans.count < @max_length
          @spans << span
        end
      end
    end
  end
end
