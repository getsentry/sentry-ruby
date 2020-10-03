require "sentry/version"
require "sentry/core_ext/object/deep_dup"
require "sentry/configuration"
require "sentry/logger"
require "sentry/event"
require "sentry/hub"
require "sentry/rack"

module Sentry
  class Error < StandardError
  end

  class << self
    def init(&block)
      config = Configuration.new
      yield(config)
      client = Client.new(config)
      scope = Scope.new
      @current_hub = Hub.new(client, scope)
    end

    def logger
      configuration.logger
    end

    def configuration
      get_current_client.configuration
    end

    def get_current_client
      get_current_hub.client
    end

    def get_current_hub
      @current_hub
    end

    def get_current_scope
      get_current_hub.current_scope
    end

    def with_scope(&block)
      get_current_hub.with_scope(&block)
    end

    def configure_scope(&block)
      get_current_hub.configure_scope(&block)
    end

    def capture_event(event)
      get_current_hub.capture_event(event)
    end

    def capture_exception(exception, **options, &block)
      get_current_hub.capture_exception(exception, **options, &block)
    end

    def capture_message(message, **options, &block)
      get_current_hub.capture_message(message, **options, &block)
    end

    def last_event_id
      get_current_hub.last_event_id
    end

    def sys_command(command)
      result = `#{command} 2>&1` rescue nil
      return if result.nil? || result.empty? || ($CHILD_STATUS && $CHILD_STATUS.exitstatus != 0)

      result.strip
    end
  end
end
