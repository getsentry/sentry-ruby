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

  META = { "name" => "sentry.ruby", "version" => Sentry::VERSION }.freeze

  LOGGER_PROGNAME = "sentry".freeze

  THREAD_LOCAL = :sentry_hub

  def self.sdk_meta
    META
  end

  class << self
    def init(&block)
      config = Configuration.new
      yield(config)
      client = Client.new(config)
      scope = Scope.new
      hub = Hub.new(client, scope)
      Thread.current[THREAD_LOCAL] = hub
      @main_hub = hub
    end

    def get_main_hub
      @main_hub
    end

    def logger
      configuration.logger
    end

    def breadcrumbs
      get_current_scope.breadcrumbs
    end

    def configuration
      get_current_client.configuration
    end

    def get_current_client
      get_current_hub.current_client
    end

    def get_current_hub
      Thread.current[THREAD_LOCAL]
    end

    def clone_hub_to_current_thread
      Thread.current[THREAD_LOCAL] = get_main_hub.clone
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
