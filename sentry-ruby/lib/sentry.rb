require "sentry/version"
require "sentry/core_ext/object/deep_dup"
require "sentry/configuration"
require "sentry/logger"
require "sentry/event"
require "sentry/hub"

module Sentry
  class Error < StandardError
  end

  class << self
    def init(&block)
      config = Configuration.new
      yield(config)
      client = Client.new(config)
      scope = Scope.new
      hub = Hub.new(client, scope)
      Thread.current[:sentry_hub] = hub
      @main_hub = hub
    end

    def get_main_hub
      @main_hub
    end

    def get_current_hub
      Thread.current[:sentry_hub]
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
