# frozen_string_literal: true

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

    include LoggingHelper

    # The name of the transaction.
    # @return [String]
    attr_reader :name

    # The sampling decision of the parent transaction, which will be considered when making the current transaction's sampling decision.
    # @return [String]
    attr_reader :parent_sampled

    # @deprecated Use Sentry.get_current_hub instead.
    attr_reader :hub

    # @deprecated Use Sentry.configuration instead.
    attr_reader :configuration

    # @deprecated Use Sentry.logger instead.
    attr_reader :logger

    def initialize(name: nil, parent_sampled: nil, hub:, **options)
      super(**options)

      @name = name
      @parent_sampled = parent_sampled
      @transaction = self
      @hub = hub
      @configuration = hub.configuration # to be removed
      @tracing_enabled = hub.configuration.tracing_enabled?
      @traces_sampler = hub.configuration.traces_sampler
      @traces_sample_rate = hub.configuration.traces_sample_rate
      @logger = hub.configuration.logger
      init_span_recorder
    end

    # Initalizes a Transaction instance with a Sentry trace string from another transaction (usually from an external request).
    #
    # The original transaction will become the parent of the new Transaction instance. And they will share the same `trace_id`.
    #
    # The child transaction will also store the parent's sampling decision in its `parent_sampled` attribute.
    # @param sentry_trace [String] the trace string from the previous transaction.
    # @param hub [Hub] the hub that'll be responsible for sending this transaction when it's finished.
    # @param options [Hash] the options you want to use to initialize a Transaction instance.
    # @return [Transaction, nil]
    def self.from_sentry_trace(sentry_trace, hub: Sentry.get_current_hub, **options)
      return unless hub.configuration.tracing_enabled?
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

      new(trace_id: trace_id, parent_span_id: parent_span_id, parent_sampled: parent_sampled, hub: hub, **options)
    end

    # @return [Hash]
    def to_hash
      hash = super
      hash.merge!(name: @name, sampled: @sampled, parent_sampled: @parent_sampled)
      hash
    end

    # @return [Transaction]
    def deep_dup
      copy = super
      copy.init_span_recorder(@span_recorder.max_length)

      @span_recorder.spans.each do |span|
        # span_recorder's first span is the current span, which should not be added to the copy's spans
        next if span == self
        copy.span_recorder.add(span.dup)
      end

      copy
    end

    # Sets initial sampling decision of the transaction.
    # @param sampling_context [Hash] a context Hash that'll be passed to `traces_sampler` (if provided).
    # @return [void]
    def set_initial_sample_decision(sampling_context:)
      unless @tracing_enabled
        @sampled = false
        return
      end

      return unless @sampled.nil?

      sample_rate =
        if @traces_sampler.is_a?(Proc)
          @traces_sampler.call(sampling_context)
        elsif !sampling_context[:parent_sampled].nil?
          sampling_context[:parent_sampled]
        else
          @traces_sample_rate
        end

      transaction_description = generate_transaction_description

      unless [true, false].include?(sample_rate) || (sample_rate.is_a?(Numeric) && sample_rate >= 0.0 && sample_rate <= 1.0)
        @sampled = false
        log_warn("#{MESSAGE_PREFIX} Discarding #{transaction_description} because of invalid sample_rate: #{sample_rate}")
        return
      end

      if sample_rate == 0.0 || sample_rate == false
        @sampled = false
        log_debug("#{MESSAGE_PREFIX} Discarding #{transaction_description} because traces_sampler returned 0 or false")
        return
      end

      if sample_rate == true
        @sampled = true
      else
        @sampled = Random.rand < sample_rate
      end

      if @sampled
        log_debug("#{MESSAGE_PREFIX} Starting #{transaction_description}")
      else
        log_debug(
          "#{MESSAGE_PREFIX} Discarding #{transaction_description} because it's not included in the random sample (sampling rate = #{sample_rate})"
        )
      end
    end

    # Finishes the transaction's recording and send it to Sentry.
    # @param hub [Hub] the hub that'll send this transaction. (Deprecated)
    # @return [TransactionEvent]
    def finish(hub: nil)
      if hub
        log_warn(
          <<~MSG
            Specifying a different hub in `Transaction#finish` will be deprecated in version 5.0.
            Please use `Hub#start_transaction` with the designated hub.
          MSG
        )
      end

      hub ||= @hub

      super() # Span#finish doesn't take arguments

      if @name.nil?
        @name = UNLABELD_NAME
      end

      if @sampled
        event = hub.current_client.event_from_transaction(self)
        hub.capture_event(event)
      else
        hub.current_client.transport.record_lost_event(:sample_rate, 'transaction')
      end
    end

    protected

    def init_span_recorder(limit = 1000)
      @span_recorder = SpanRecorder.new(limit)
      @span_recorder.add(self)
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
