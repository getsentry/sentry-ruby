# frozen_string_literal: true

require "sentry/baggage"
require "sentry/profiler"
require "sentry/utils/sample_rand"
require "sentry/propagation_context"

module Sentry
  class Transaction < Span
    UNLABELD_NAME = "<unlabeled transaction>"
    MESSAGE_PREFIX = "[Tracing]"

    # https://develop.sentry.dev/sdk/event-payloads/transaction/#transaction-annotations
    SOURCES = %i[custom url route view component task]

    include LoggingHelper

    # The name of the transaction.
    # @return [String]
    attr_reader :name

    # The source of the transaction name.
    # @return [Symbol]
    attr_reader :source

    # The sampling decision of the parent transaction, which will be considered when making the current transaction's sampling decision.
    # @return [String]
    attr_reader :parent_sampled

    # The parsed incoming W3C baggage header.
    # This is only for accessing the current baggage variable.
    # Please use the #get_baggage method for interfacing outside this class.
    # @return [Baggage, nil]
    attr_reader :baggage

    # The measurements added to the transaction.
    # @return [Hash]
    attr_reader :measurements

    # The effective sample rate at which this transaction was sampled.
    # @return [Float, nil]
    attr_reader :effective_sample_rate

    # Additional contexts stored directly on the transaction object.
    # @return [Hash]
    attr_reader :contexts

    # The Profiler instance for this transaction.
    # @return [Profiler]
    attr_reader :profiler

    # Sample rand value generated from trace_id
    # @return [String]
    attr_reader :sample_rand

    def initialize(
      name: nil,
      source: :custom,
      parent_sampled: nil,
      baggage: nil,
      sample_rand: nil,
      **options
    )
      super(transaction: self, **options)

      set_name(name, source: source)
      @parent_sampled = parent_sampled
      @baggage = baggage
      @effective_sample_rate = nil
      @contexts = {}
      @measurements = {}
      @sample_rand = sample_rand

      init_span_recorder
      init_profiler

      unless @sample_rand
        generator = Utils::SampleRand.new(trace_id: @trace_id)
        @sample_rand = generator.generate_from_trace_id
      end
    end

    # @return [Hash]
    def to_h
      hash = super

      hash.merge!(
        name: @name,
        source: @source,
        sampled: @sampled,
        parent_sampled: @parent_sampled
      )

      hash
    end

    def parent_sample_rate
      return unless @baggage&.items

      sample_rate_str = @baggage.items["sample_rate"]
      sample_rate_str&.to_f
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

    # Sets a custom measurement on the transaction.
    # @param name [String] name of the measurement
    # @param value [Float] value of the measurement
    # @param unit [String] unit of the measurement
    # @return [void]
    def set_measurement(name, value, unit = "")
      @measurements[name] = { value: value, unit: unit }
    end

    # Sets initial sampling decision of the transaction.
    # @param sampling_context [Hash] a context Hash that'll be passed to `traces_sampler` (if provided).
    # @return [void]
    def set_initial_sample_decision(sampling_context:)
      configuration = Sentry.configuration

      unless configuration && configuration.tracing_enabled?
        @sampled = false
        return
      end

      unless @sampled.nil?
        @effective_sample_rate = @sampled ? 1.0 : 0.0
        return
      end

      sample_rate =
        if configuration.traces_sampler.is_a?(Proc)
          configuration.traces_sampler.call(sampling_context)
        elsif !sampling_context[:parent_sampled].nil?
          sampling_context[:parent_sampled]
        else
          configuration.traces_sample_rate
        end

      transaction_description = generate_transaction_description

      if [true, false].include?(sample_rate)
        @effective_sample_rate = sample_rate ? 1.0 : 0.0
      elsif sample_rate.is_a?(Numeric) && sample_rate >= 0.0 && sample_rate <= 1.0
        @effective_sample_rate = sample_rate.to_f
      else
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
        if Sentry.backpressure_monitor
          factor = Sentry.backpressure_monitor.downsample_factor
          @effective_sample_rate /= 2**factor
        end

        @sampled = @sample_rand < @effective_sample_rate
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
    # @return [TransactionEvent]
    def finish(end_timestamp: nil)
      super(end_timestamp: end_timestamp)

      if @name.nil?
        @name = UNLABELD_NAME
      end

      hub = Sentry.get_current_hub
      return unless hub

      hub.stop_profiler!(self)

      if @sampled && ignore_status_code?
        @sampled = false

        status_code = get_http_status_code
        log_debug("#{MESSAGE_PREFIX} Discarding #{generate_transaction_description} due to ignored HTTP status code: #{status_code}")

        hub.current_client.transport.record_lost_event(:event_processor, "transaction")
        hub.current_client.transport.record_lost_event(:event_processor, "span")
      elsif @sampled
        event = hub.current_client.event_from_transaction(self)
        hub.capture_event(event)
      else
        is_backpressure = Sentry.backpressure_monitor&.downsample_factor&.positive?
        reason = is_backpressure ? :backpressure : :sample_rate
        hub.current_client.transport.record_lost_event(reason, "transaction")
        hub.current_client.transport.record_lost_event(reason, "span")
      end
    end

    # Get the existing frozen incoming baggage
    # or populate one with sentry- items as the head SDK.
    # @return [Baggage]
    def get_baggage
      populate_head_baggage if @baggage.nil? || @baggage.mutable
      @baggage
    end

    # Set the transaction name directly.
    # Considered internal api since it bypasses the usual scope logic.
    # @param name [String]
    # @param source [Symbol]
    # @return [void]
    def set_name(name, source: :custom)
      @name = name
      @source = SOURCES.include?(source) ? source.to_sym : :custom
    end

    # Set contexts directly on the transaction.
    # @param key [String, Symbol]
    # @param value [Object]
    # @return [void]
    def set_context(key, value)
      @contexts[key] = value
    end

    # Start the profiler.
    # @return [void]
    def start_profiler!
      return unless profiler

      profiler.set_initial_sample_decision(sampled)
      profiler.start
    end

    # These are high cardinality and thus bad
    def source_low_quality?
      source == :url
    end

    protected

    def init_span_recorder(limit = 1000)
      @span_recorder = SpanRecorder.new(limit)
      @span_recorder.add(self)
    end

    def init_profiler
      hub = Sentry.get_current_hub
      return unless hub

      unless hub.profiler_running?
        @profiler = hub.configuration.profiler_class.new(hub.configuration)
      end
    end

    private

    def generate_transaction_description
      result = op.nil? ? "" : "<#{@op}> "
      result += "transaction"
      result += " <#{@name}>" if @name
      result
    end

    def populate_head_baggage
      configuration = Sentry.configuration

      items = {
        "trace_id" => trace_id,
        "sample_rate" => effective_sample_rate&.to_s,
        "sample_rand" => Utils::SampleRand.format(@sample_rand),
        "sampled" => sampled&.to_s,
        "environment" => configuration&.environment,
        "release" => configuration&.release,
        "public_key" => configuration&.dsn&.public_key
      }

      items["transaction"] = name unless source_low_quality?

      items.compact!
      @baggage = Baggage.new(items, mutable: false)
    end

    def ignore_status_code?
      trace_ignore_status_codes = Sentry.configuration&.trace_ignore_status_codes
      return false unless trace_ignore_status_codes

      status_code = get_http_status_code
      return false unless status_code

      trace_ignore_status_codes.any? do |ignored|
        ignored.is_a?(Range) ? ignored.include?(status_code) : status_code == ignored
      end
    end

    def get_http_status_code
      @data && @data[Span::DataConventions::HTTP_STATUS_CODE]
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
