require "sentry/transport"
require 'sentry/utils/deep_merge'

module Sentry
  class Client
    attr_reader :transport, :configuration

    def initialize(configuration)
      @configuration = configuration
      @transport =
        case configuration.dsn&.scheme
        when 'http', 'https'
          HTTPTransport.new(configuration)
        else
          DummyTransport.new(configuration)
        end
    end

    def capture_exception(exception, scope:, **options, &block)
      event = event_from_exception(exception, **options)
      block.call(event) if block
      capture_event(event, scope)
    end

    def capture_message(message, scope:, **options, &block)
      event = event_from_message(message, **options)
      block.call(event) if block
      capture_event(event, scope)
    end

    def capture_event(event, scope)
      scope.apply_to_event(event)
      send_event(event)
      event
    end

    def event_from_exception(exception, **options)
      exception_context =
        if exception.instance_variable_defined?(:@__sentry_context)
          exception.instance_variable_get(:@__sentry_context)
        elsif exception.respond_to?(:sentry_context)
          exception.sentry_context
        else
          {}
        end

      options = Utils::DeepMergeHash.deep_merge(exception_context, options)

      return unless @configuration.exception_class_allowed?(exception)

      options = Event::Options.new(**options)

      Event.new(configuration: configuration, options: options) do |evt|
        evt.add_exception_interface(exception)
      end
    end

    def event_from_message(message, **options)
      options.merge!(message: message)
      options = Event::Options.new(options)
      Event.new(configuration: configuration, options: options)
    end

    def send_event(event, hint = nil)
      return false unless configuration.sending_allowed?(event)

      event = configuration.before_send.call(event, hint) if configuration.before_send
      if event.nil?
        configuration.logger.info "Discarded event because before_send returned nil"
        return
      end

      transport.send_event(event)

      event
    end
  end
end
