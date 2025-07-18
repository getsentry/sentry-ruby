# frozen_string_literal: true

require "sentry/transport"
require "sentry/log_event"
require "sentry/log_event_buffer"
require "sentry/utils/uuid"

module Sentry
  class Client
    include LoggingHelper

    # The Transport object that'll send events for the client.
    # @return [Transport]
    attr_reader :transport

    # The Transport object that'll send events for the client.
    # @return [SpotlightTransport, nil]
    attr_reader :spotlight_transport

    # @!visibility private
    attr_reader :log_event_buffer

    # @!macro configuration
    attr_reader :configuration

    # @param configuration [Configuration]
    def initialize(configuration)
      @configuration = configuration
      @sdk_logger = configuration.sdk_logger

      if transport_class = configuration.transport.transport_class
        @transport = transport_class.new(configuration)
      else
        @transport =
          case configuration.dsn&.scheme
          when "http", "https"
            HTTPTransport.new(configuration)
          else
            DummyTransport.new(configuration)
          end
      end

      @spotlight_transport = SpotlightTransport.new(configuration) if configuration.spotlight

      if configuration.enable_logs
        @log_event_buffer = LogEventBuffer.new(configuration, self).start
      end
    end

    # Applies the given scope's data to the event and sends it to Sentry.
    # @param event [Event] the event to be sent.
    # @param scope [Scope] the scope with contextual data that'll be applied to the event before it's sent.
    # @param hint [Hash] the hint data that'll be passed to `before_send` callback and the scope's event processors.
    # @return [Event, nil]
    def capture_event(event, scope, hint = {})
      return unless configuration.sending_allowed?

      if event.is_a?(ErrorEvent) && !configuration.sample_allowed?
        transport.record_lost_event(:sample_rate, "error")
        return
      end

      event_type = event.is_a?(Event) ? event.type : event["type"]
      data_category = Envelope::Item.data_category(event_type)

      is_transaction = event.is_a?(TransactionEvent)
      spans_before = is_transaction ? event.spans.size : 0

      event = scope.apply_to_event(event, hint)

      if event.nil?
        log_debug("Discarded event because one of the event processors returned nil")
        transport.record_lost_event(:event_processor, data_category)
        transport.record_lost_event(:event_processor, "span", num: spans_before + 1) if is_transaction
        return
      elsif is_transaction
        spans_delta = spans_before - event.spans.size
        transport.record_lost_event(:event_processor, "span", num: spans_delta) if spans_delta > 0
      end

      if async_block = configuration.async
        dispatch_async_event(async_block, event, hint)
      elsif configuration.background_worker_threads != 0 && hint.fetch(:background, true)
        unless dispatch_background_event(event, hint)
          transport.record_lost_event(:queue_overflow, data_category)
          transport.record_lost_event(:queue_overflow, "span", num: spans_before + 1) if is_transaction
        end
      else
        send_event(event, hint)
      end

      event
    rescue => e
      log_error("Event capturing failed", e, debug: configuration.debug)
      nil
    end

    # Buffer a log event to be sent later with other logs in a single envelope
    # @param event [LogEvent] the log event to be buffered
    # @return [LogEvent]
    def buffer_log_event(event, scope)
      return unless event.is_a?(LogEvent)
      @log_event_buffer.add_event(scope.apply_to_event(event))
      event
    end

    # Capture an envelope directly.
    # @param envelope [Envelope] the envelope to be captured.
    # @return [void]
    def capture_envelope(envelope)
      Sentry.background_worker.perform { send_envelope(envelope) }
    end

    # Flush pending events to Sentry.
    # @return [void]
    def flush
      transport.flush if configuration.sending_to_dsn_allowed?
      spotlight_transport.flush if spotlight_transport
      @log_event_buffer&.flush
    end

    # Initializes an Event object with the given exception. Returns `nil` if the exception's class is excluded from reporting.
    # @param exception [Exception] the exception to be reported.
    # @param hint [Hash] the hint data that'll be passed to `before_send` callback and the scope's event processors.
    # @return [Event, nil]
    def event_from_exception(exception, hint = {})
      return unless @configuration.sending_allowed?

      ignore_exclusions = hint.delete(:ignore_exclusions) { false }
      return if !ignore_exclusions && !@configuration.exception_class_allowed?(exception)

      integration_meta = Sentry.integrations[hint[:integration]]
      mechanism = hint.delete(:mechanism) { Mechanism.new }

      ErrorEvent.new(configuration: configuration, integration_meta: integration_meta).tap do |event|
        event.add_exception_interface(exception, mechanism: mechanism)
        event.add_threads_interface(crashed: true)
        event.level = :error
      end
    end

    # Initializes an Event object with the given message.
    # @param message [String] the message to be reported.
    # @param hint [Hash] the hint data that'll be passed to `before_send` callback and the scope's event processors.
    # @return [Event]
    def event_from_message(message, hint = {}, backtrace: nil)
      return unless @configuration.sending_allowed?

      integration_meta = Sentry.integrations[hint[:integration]]
      event = ErrorEvent.new(configuration: configuration, integration_meta: integration_meta, message: message)
      event.add_threads_interface(backtrace: backtrace || caller)
      event.level = :error
      event
    end

    # Initializes a CheckInEvent object with the given options.
    #
    # @param slug [String] identifier of this monitor
    # @param status [Symbol] status of this check-in, one of {CheckInEvent::VALID_STATUSES}
    # @param hint [Hash] the hint data that'll be passed to `before_send` callback and the scope's event processors.
    # @param duration [Integer, nil] seconds elapsed since this monitor started
    # @param monitor_config [Cron::MonitorConfig, nil] configuration for this monitor
    # @param check_in_id [String, nil] for updating the status of an existing monitor
    #
    # @return [Event]
    def event_from_check_in(
      slug,
      status,
      hint = {},
      duration: nil,
      monitor_config: nil,
      check_in_id: nil
    )
      return unless configuration.sending_allowed?

      CheckInEvent.new(
        configuration: configuration,
        integration_meta: Sentry.integrations[hint[:integration]],
        slug: slug,
        status: status,
        duration: duration,
        monitor_config: monitor_config,
        check_in_id: check_in_id
      )
    end

    # Initializes a LogEvent object with the given message and options
    #
    # @param message [String] the log message
    # @param level [Symbol] the log level (:trace, :debug, :info, :warn, :error, :fatal)
    # @param options [Hash] additional options
    # @option options [Array] :parameters Array of values to replace template tokens in the message
    #
    # @return [LogEvent] the created log event
    def event_from_log(message, level:, **options)
      return unless configuration.sending_allowed?

      attributes = options.reject { |k, _| k == :level || k == :severity }

      LogEvent.new(level: level, body: message, attributes: attributes)
    end

    # Initializes an Event object with the given Transaction object.
    # @param transaction [Transaction] the transaction to be recorded.
    # @return [TransactionEvent]
    def event_from_transaction(transaction)
      TransactionEvent.new(configuration: configuration, transaction: transaction)
    end

    # @!macro send_event
    def send_event(event, hint = nil)
      event_type = event.is_a?(Event) ? event.type : event["type"]
      data_category = Envelope::Item.data_category(event_type)
      spans_before = event.is_a?(TransactionEvent) ? event.spans.size : 0

      if event_type != TransactionEvent::TYPE && configuration.before_send
        event = configuration.before_send.call(event, hint)

        case event
        when ErrorEvent, CheckInEvent
          # do nothing
        when Hash
          log_debug(<<~MSG)
            Returning a Hash from before_send is deprecated and will be removed in the next major version.
            Please return a Sentry::ErrorEvent object instead.
          MSG
        else
          # Avoid serializing the event object in this case because we aren't sure what it is and what it contains
          log_debug(<<~MSG)
            Discarded event because before_send didn't return a Sentry::ErrorEvent object but an instance of #{event.class}
          MSG
          transport.record_lost_event(:before_send, data_category)
          return
        end
      end

      if event_type == TransactionEvent::TYPE && configuration.before_send_transaction
        event = configuration.before_send_transaction.call(event, hint)

        if event.is_a?(TransactionEvent) || event.is_a?(Hash)
          spans_after = event.is_a?(TransactionEvent) ? event.spans.size : 0
          spans_delta = spans_before - spans_after
          transport.record_lost_event(:before_send, "span", num: spans_delta) if spans_delta > 0

          if event.is_a?(Hash)
            log_debug(<<~MSG)
              Returning a Hash from before_send_transaction is deprecated and will be removed in the next major version.
              Please return a Sentry::TransactionEvent object instead.
            MSG
          end
        else
          # Avoid serializing the event object in this case because we aren't sure what it is and what it contains
          log_debug(<<~MSG)
            Discarded event because before_send_transaction didn't return a Sentry::TransactionEvent object but an instance of #{event.class}
          MSG
          transport.record_lost_event(:before_send, "transaction")
          transport.record_lost_event(:before_send, "span", num: spans_before + 1)
          return
        end
      end

      transport.send_event(event) if configuration.sending_to_dsn_allowed?
      spotlight_transport.send_event(event) if spotlight_transport

      event
    rescue => e
      log_error("Event sending failed", e, debug: configuration.debug)
      transport.record_lost_event(:network_error, data_category)
      transport.record_lost_event(:network_error, "span", num: spans_before + 1) if event.is_a?(TransactionEvent)
      raise
    end

    # Send an envelope with batched logs
    # @param log_events [Array<LogEvent>] the log events to be sent
    # @api private
    # @return [void]
    def send_logs(log_events)
      envelope = Envelope.new(
        event_id: Sentry::Utils.uuid,
        sent_at: Sentry.utc_now.iso8601,
        dsn: configuration.dsn,
        sdk: Sentry.sdk_meta
      )

      discarded_count = 0
      envelope_items = []

      if configuration.before_send_log
        log_events.each do |log_event|
          processed_log_event = configuration.before_send_log.call(log_event)

          if processed_log_event
            envelope_items << processed_log_event.to_hash
          else
            discarded_count += 1
          end
        end

        envelope_items
      else
        envelope_items = log_events.map(&:to_hash)
      end

      envelope.add_item(
        {
          type: "log",
          item_count: envelope_items.size,
          content_type: "application/vnd.sentry.items.log+json"
        },
        { items: envelope_items }
      )

      send_envelope(envelope)

      unless discarded_count.zero?
        transport.record_lost_event(:before_send, "log_item", num: discarded_count)
      end
    end

    # Send an envelope directly to Sentry.
    # @param envelope [Envelope] the envelope to be sent.
    # @return [void]
    def send_envelope(envelope)
      transport.send_envelope(envelope) if configuration.sending_to_dsn_allowed?
      spotlight_transport.send_envelope(envelope) if spotlight_transport
    rescue => e
      log_error("Envelope sending failed", e, debug: configuration.debug)

      envelope.items.map(&:data_category).each do |data_category|
        transport.record_lost_event(:network_error, data_category)
      end

      raise
    end

    # @deprecated use Sentry.get_traceparent instead.
    #
    # Generates a Sentry trace for distribted tracing from the given Span.
    # Returns `nil` if `config.propagate_traces` is `false`.
    # @param span [Span] the span to generate trace from.
    # @return [String, nil]
    def generate_sentry_trace(span)
      return unless configuration.propagate_traces

      trace = span.to_sentry_trace
      log_debug("[Tracing] Adding #{SENTRY_TRACE_HEADER_NAME} header to outgoing request: #{trace}")
      trace
    end

    # @deprecated Use Sentry.get_baggage instead.
    #
    # Generates a W3C Baggage header for distributed tracing from the given Span.
    # Returns `nil` if `config.propagate_traces` is `false`.
    # @param span [Span] the span to generate trace from.
    # @return [String, nil]
    def generate_baggage(span)
      return unless configuration.propagate_traces

      baggage = span.to_baggage

      if baggage && !baggage.empty?
        log_debug("[Tracing] Adding #{BAGGAGE_HEADER_NAME} header to outgoing request: #{baggage}")
      end

      baggage
    end

    private

    def dispatch_background_event(event, hint)
      Sentry.background_worker.perform do
        send_event(event, hint)
      end
    end

    def dispatch_async_event(async_block, event, hint)
      # We have to convert to a JSON-like hash, because background job
      # processors (esp ActiveJob) may not like weird types in the event hash

      event_hash =
        begin
          event.to_json_compatible
        rescue => e
          log_error("Converting #{event.type} (#{event.event_id}) to JSON compatible hash failed", e, debug: configuration.debug)
          return
        end

      if async_block.arity == 2
        hint = JSON.parse(JSON.generate(hint))
        async_block.call(event_hash, hint)
      else
        async_block.call(event_hash)
      end
    rescue => e
      log_error("Async #{event_hash["type"]} sending failed", e, debug: configuration.debug)
      send_event(event, hint)
    end
  end
end
