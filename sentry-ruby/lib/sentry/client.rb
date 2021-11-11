require "sentry/transport"

module Sentry
  class Client
    include LoggingHelper

    attr_reader :transport, :configuration, :logger

    def initialize(configuration)
      @configuration = configuration
      @logger = configuration.logger

      if transport_class = configuration.transport.transport_class
        @transport = transport_class.new(configuration)
      else
        @transport =
          case configuration.dsn&.scheme
          when 'http', 'https'
            HTTPTransport.new(configuration)
          else
            DummyTransport.new(configuration)
          end
      end
    end

    def capture_event(event, scope, hint = {})
      return unless configuration.sending_allowed?

      unless event.is_a?(TransactionEvent) || configuration.sample_allowed?
        transport.record_lost_event(:sample_rate, 'event')
        return
      end

      event_type = event.is_a?(Event) ? event.type : event["type"]
      event = scope.apply_to_event(event, hint)

      if event.nil?
        log_info("Discarded event because one of the event processors returned nil")
        transport.record_lost_event(:event_processor, event_type)
        return
      end

      if async_block = configuration.async
        dispatch_async_event(async_block, event, hint)
      elsif configuration.background_worker_threads != 0 && hint.fetch(:background, true)
        queued = dispatch_background_event(event, hint)
        transport.record_lost_event(:queue_overflow, event_type) unless queued
      else
        send_event(event, hint)
      end

      event
    rescue => e
      log_error("Event capturing failed", e, debug: configuration.debug)
      nil
    end

    def event_from_exception(exception, hint = {})
      integration_meta = Sentry.integrations[hint[:integration]]
      return unless @configuration.exception_class_allowed?(exception)

      Event.new(configuration: configuration, integration_meta: integration_meta).tap do |event|
        event.add_exception_interface(exception)
        event.add_threads_interface(crashed: true)
      end
    end

    def event_from_message(message, hint = {}, backtrace: nil)
      integration_meta = Sentry.integrations[hint[:integration]]
      event = Event.new(configuration: configuration, integration_meta: integration_meta, message: message)
      event.add_threads_interface(backtrace: backtrace || caller)
      event
    end

    def event_from_transaction(transaction)
      TransactionEvent.new(configuration: configuration).tap do |event|
        event.transaction = transaction.name
        event.contexts.merge!(trace: transaction.get_trace_context)
        event.timestamp = transaction.timestamp
        event.start_timestamp = transaction.start_timestamp

        finished_spans = transaction.span_recorder.spans.select { |span| span.timestamp && span != transaction }
        event.spans = finished_spans.map(&:to_hash)
      end
    end

    def send_event(event, hint = nil)
      event_type = event.is_a?(Event) ? event.type : event["type"]

      if event_type != TransactionEvent::TYPE && configuration.before_send
        event = configuration.before_send.call(event, hint)

        if event.nil?
          log_info("Discarded event because before_send returned nil")
          transport.record_lost_event(:before_send, 'event')
          return
        end
      end

      transport.send_event(event)

      event
    rescue => e
      loggable_event_type = (event_type || "event").capitalize
      log_error("#{loggable_event_type} sending failed", e, debug: configuration.debug)

      event_info = Event.get_log_message(event.to_hash)
      log_info("Unreported #{loggable_event_type}: #{event_info}")
      transport.record_lost_event(:network_error, event_type)
      raise
    end

    def generate_sentry_trace(span)
      return unless configuration.propagate_traces

      trace = span.to_sentry_trace
      log_debug("[Tracing] Adding #{SENTRY_TRACE_HEADER_NAME} header to outgoing request: #{trace}")
      trace
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
      event_hash = event.to_json_compatible

      if async_block.arity == 2
        hint = JSON.parse(JSON.generate(hint))
        async_block.call(event_hash, hint)
      else
        async_block.call(event_hash)
      end
    rescue => e
      loggable_event_type = event_hash["type"] || "event"
      log_error("Async #{loggable_event_type} sending failed", e, debug: configuration.debug)
      send_event(event, hint)
    end
  end
end
