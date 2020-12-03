require "sentry/transport"

module Sentry
  class Client
    attr_reader :transport, :configuration

    def initialize(configuration)
      @configuration = configuration

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

    def capture_event(event, scope, hint = nil)
      scope.apply_to_event(event, hint)

      if configuration.async?
        begin
          # We have to convert to a JSON-like hash, because background job
          # processors (esp ActiveJob) may not like weird types in the event hash
          configuration.async.call(event.to_json_compatible)
        rescue => e
          configuration.logger.error(LOGGER_PROGNAME) { "async event sending failed: #{e.message}" }
          send_event(event, hint)
        end
      else
        send_event(event, hint)
      end

      event
    end

    def event_from_exception(exception)
      return unless @configuration.exception_class_allowed?(exception)

      Event.new(configuration: configuration).tap do |event|
        event.add_exception_interface(exception)
      end
    end

    def event_from_message(message)
      Event.new(configuration: configuration, message: message)
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
      return false unless configuration.sending_allowed?

      event = configuration.before_send.call(event, hint) if configuration.before_send
      if event.nil?
        configuration.logger.info(LOGGER_PROGNAME) { "Discarded event because before_send returned nil" }
        return
      end

      transport.send_event(event)

      event
    end
  end
end
