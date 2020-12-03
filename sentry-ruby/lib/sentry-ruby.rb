require "forwardable"

require "sentry/version"
require "sentry/core_ext/object/deep_dup"
require "sentry/configuration"
require "sentry/logger"
require "sentry/event"
require "sentry/transaction_event"
require "sentry/span"
require "sentry/transaction"
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

  def self.utc_now
    Time.now.utc
  end

  class << self
    extend Forwardable

    def_delegators :get_current_scope, :set_tags, :set_extras, :set_user

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

    def add_breadcrumb(breadcrumb, &block)
      get_current_scope.breadcrumbs.record(breadcrumb, &block)
    end

    def configuration
      get_current_client.configuration
    end

    def get_current_client
      get_current_hub.current_client
    end

    def get_current_hub
      # we need to assign a hub to the current thread if it doesn't have one yet
      #
      # ideally, we should do this proactively whenever a new thread is created
      # but it's impossible for the SDK to keep track every new thread
      # so we need to use this rather passive way to make sure the app doesn't crash
      Thread.current[THREAD_LOCAL] || clone_hub_to_current_thread
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

    def send_event(event)
      get_current_client.send_event(event)
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

    def start_transaction(**options)
      get_current_hub.start_transaction(**options)
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
