require "English"
require "forwardable"
require "time"

require "sentry/version"
require "sentry/exceptions"
require "sentry/core_ext/object/deep_dup"
require "sentry/utils/argument_checking_helper"
require "sentry/utils/logging_helper"
require "sentry/configuration"
require "sentry/logger"
require "sentry/event"
require "sentry/transaction_event"
require "sentry/span"
require "sentry/transaction"
require "sentry/hub"
require "sentry/background_worker"


[
  "sentry/rake",
  "sentry/rack",
].each do |lib|
  begin
    require lib
  rescue LoadError
  end
end

module Sentry
  META = { "name" => "sentry.ruby", "version" => Sentry::VERSION }.freeze

  LOGGER_PROGNAME = "sentry".freeze

  SENTRY_TRACE_HEADER_NAME = "sentry-trace".freeze

  THREAD_LOCAL = :sentry_hub

  class << self
    def exception_locals_tp
      @exception_locals_tp ||= TracePoint.new(:raise) do |tp|
        exception = tp.raised_exception

        # don't collect locals again if the exception is re-raised
        next if exception.instance_variable_get(:@sentry_locals)
        next unless tp.binding

        locals = tp.binding.local_variables.each_with_object({}) do |local, result|
          result[local] = tp.binding.local_variable_get(local)
        end

        exception.instance_variable_set(:@sentry_locals, locals)
      end
    end

    attr_accessor :background_worker

    ##### Patch Registration #####
    #
    def register_patch(&block)
      registered_patches << block
    end

    def apply_patches(config)
      registered_patches.each do |patch|
        patch.call(config)
      end
    end

    def registered_patches
      @registered_patches ||= []
    end

    ##### Integrations #####
    #
    # Returns a hash that contains all the integrations that have been registered to the main SDK.
    def integrations
      @integrations ||= {}
    end

    # Registers the SDK integration with its name and version.
    def register_integration(name, version)
      meta = { name: "sentry.ruby.#{name}", version: version }.freeze
      integrations[name.to_s] = meta
    end

    ##### Method Delegation #####
    #
    extend Forwardable

    def_delegators :get_current_client, :configuration, :send_event
    def_delegators :get_current_scope, :set_tags, :set_extras, :set_user, :set_context

    ##### Main APIs #####
    #
    def init(&block)
      config = Configuration.new
      yield(config) if block_given?
      config.detect_release
      apply_patches(config)
      client = Client.new(config)
      scope = Scope.new(max_breadcrumbs: config.max_breadcrumbs)
      hub = Hub.new(client, scope)
      Thread.current.thread_variable_set(THREAD_LOCAL, hub)
      @main_hub = hub
      @background_worker = Sentry::BackgroundWorker.new(config)

      if config.capture_exception_frame_locals
        exception_locals_tp.enable
      end
    end

    # Returns an uri for security policy reporting that's generated from the given DSN
    # (To learn more about security policy reporting: https://docs.sentry.io/product/security-policy-reporting/)
    #
    # It returns nil if
    #
    # 1. The SDK is not initialized yet.
    # 2. The DSN is not provided or is invalid.
    def csp_report_uri
      return unless initialized?
      configuration.csp_report_uri
    end

    # Returns the main thread's active hub.
    def get_main_hub
      @main_hub
    end

    # Takes an instance of Sentry::Breadcrumb and stores it to the current active scope.
    def add_breadcrumb(breadcrumb, **options)
      get_current_hub&.add_breadcrumb(breadcrumb, **options)
    end

    # Returns the current active hub.
    # If the current thread doesn't have an active hub, it will clone the main thread's active hub,
    # stores it in the current thread, and then returns it.
    def get_current_hub
      # we need to assign a hub to the current thread if it doesn't have one yet
      #
      # ideally, we should do this proactively whenever a new thread is created
      # but it's impossible for the SDK to keep track every new thread
      # so we need to use this rather passive way to make sure the app doesn't crash
      Thread.current.thread_variable_get(THREAD_LOCAL) || clone_hub_to_current_thread
    end

    # Returns the current active client.
    def get_current_client
      get_current_hub&.current_client
    end

    # Returns the current active scope.
    def get_current_scope
      get_current_hub&.current_scope
    end

    # Clones the main thread's active hub and stores it to the current thread.
    def clone_hub_to_current_thread
      Thread.current.thread_variable_set(THREAD_LOCAL, get_main_hub.clone)
    end

    # Takes a block and yields the current active scope.
    #
    # ```ruby
    # Sentry.configure_scope do |scope|
    #   scope.set_tags(foo: "bar")
    # end
    #
    # Sentry.capture_message("test message") # this event will have tags { foo: "bar" }
    # ```
    #
    def configure_scope(&block)
      get_current_hub&.configure_scope(&block)
    end

    # Takes a block and yields a temporary scope.
    # The temporary scope will inherit all the attributes from the current active scope and replace it to be the active
    # scope inside the block. For example:
    #
    # ```ruby
    # Sentry.configure_scope do |scope|
    #   scope.set_tags(foo: "bar")
    # end
    #
    # Sentry.capture_message("test message") # this event will have tags { foo: "bar" }
    #
    # Sentry.with_scope do |temp_scope|
    #   temp_scope.set_tags(foo: "baz")
    #   Sentry.capture_message("test message 2") # this event will have tags { foo: "baz" }
    # end
    #
    # Sentry.capture_message("test message 3") # this event will have tags { foo: "bar" }
    # ```
    #
    def with_scope(&block)
      get_current_hub&.with_scope(&block)
    end

    # Takes an exception and reports it to Sentry via the currently active hub.
    def capture_exception(exception, **options, &block)
      get_current_hub&.capture_exception(exception, **options, &block)
    end

    # Takes a message string and reports it to Sentry via the currently active hub.
    def capture_message(message, **options, &block)
      get_current_hub&.capture_message(message, **options, &block)
    end

    # Takes an instance of Sentry::Event and dispatches it to the currently active hub.
    def capture_event(event)
      get_current_hub&.capture_event(event)
    end

    # Takes or initializes a new Sentry::Transaction and makes a sampling decision for it.
    def start_transaction(**options)
      get_current_hub&.start_transaction(**options)
    end

    # Returns the id of the lastly reported Sentry::Event.
    def last_event_id
      get_current_hub&.last_event_id
    end


    ##### Helpers #####
    #
    def sys_command(command)
      result = `#{command} 2>&1` rescue nil
      return if result.nil? || result.empty? || ($CHILD_STATUS && $CHILD_STATUS.exitstatus != 0)

      result.strip
    end

    def initialized?
      !!@main_hub
    end

    def logger
      configuration.logger
    end

    def sdk_meta
      META
    end

    def utc_now
      Time.now.utc
    end
  end
end

# patches
require "sentry/net/http"
