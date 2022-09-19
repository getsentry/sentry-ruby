# frozen_string_literal: true

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
require "sentry/error_event"
require "sentry/transaction_event"
require "sentry/span"
require "sentry/transaction"
require "sentry/hub"
require "sentry/background_worker"
require "sentry/session_flusher"

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

  CAPTURED_SIGNATURE = :@__sentry_captured

  LOGGER_PROGNAME = "sentry".freeze

  SENTRY_TRACE_HEADER_NAME = "sentry-trace".freeze

  BAGGAGE_HEADER_NAME = "baggage".freeze

  THREAD_LOCAL = :sentry_hub

  class << self
    # @!visibility private
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

    # @!attribute [rw] background_worker
    #   @return [BackgroundWorker, nil]
    attr_accessor :background_worker

    # @!attribute [r] session_flusher
    #   @return [SessionFlusher, nil]
    attr_reader :session_flusher

    ##### Patch Registration #####

    # @!visibility private
    def register_patch(&block)
      registered_patches << block
    end

    # @!visibility private
    def apply_patches(config)
      registered_patches.each do |patch|
        patch.call(config)
      end
    end

    # @!visibility private
    def registered_patches
      @registered_patches ||= []
    end

    ##### Integrations #####

    # Returns a hash that contains all the integrations that have been registered to the main SDK.
    #
    # @return [Hash{String=>Hash}]
    def integrations
      @integrations ||= {}
    end

    # Registers the SDK integration with its name and version.
    #
    # @param name [String] name of the integration
    # @param version [String] version of the integration
    def register_integration(name, version)
      if initialized?
        logger.warn(LOGGER_PROGNAME) do
          <<~MSG
            Integration '#{name}' is loaded after the SDK is initialized, which can cause unexpected behavior.  Please make sure all integrations are loaded before SDK initialization.
          MSG
        end
      end

      meta = { name: "sentry.ruby.#{name}", version: version }.freeze
      integrations[name.to_s] = meta
    end

    ##### Method Delegation #####

    extend Forwardable

    # @!macro [new] configuration
    #   The Configuration object that's used for configuring the client and its transport.
    #   @return [Configuration]
    # @!macro [new] send_event
    #   Sends the event to Sentry.
    #   @param event [Event] the event to be sent.
    #   @param hint [Hash] the hint data that'll be passed to `before_send` callback.
    #   @return [Event]

    # @!method configuration
    #   @!macro configuration
    def configuration
      return unless initialized?
      get_current_client.configuration
    end

    # @!method send_event
    #   @!macro send_event
    def send_event(*args)
      return unless initialized?
      get_current_client.send_event(*args)
    end

    # @!macro [new] set_extras
    #   Updates the scope's extras attribute by merging with the old value.
    #   @param extras [Hash]
    #   @return [Hash]
    # @!macro [new] set_user
    #   Sets the scope's user attribute.
    #   @param user [Hash]
    #   @return [Hash]
    # @!macro [new] set_context
    #   Adds a new key-value pair to current contexts.
    #   @param key [String, Symbol]
    #   @param value [Object]
    #   @return [Hash]
    # @!macro [new] set_tags
    #   Updates the scope's tags attribute by merging with the old value.
    #   @param tags [Hash]
    #   @return [Hash]

    # @!method set_tags
    #   @!macro set_tags
    def set_tags(*args)
      return unless initialized?
      get_current_scope.set_tags(*args)
    end

    # @!method set_extras
    #   @!macro set_extras
    def set_extras(*args)
      return unless initialized?
      get_current_scope.set_extras(*args)
    end

    # @!method set_user
    #   @!macro set_user
    def set_user(*args)
      return unless initialized?
      get_current_scope.set_user(*args)
    end

    # @!method set_context
    #   @!macro set_context
    def set_context(*args)
      return unless initialized?
      get_current_scope.set_context(*args)
    end

    ##### Main APIs #####

    # Initializes the SDK with given configuration.
    #
    # @yieldparam config [Configuration]
    # @return [void]
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

      @session_flusher = if config.auto_session_tracking
                           Sentry::SessionFlusher.new(config, client)
                         else
                           nil
                         end

      if config.capture_exception_frame_locals
        exception_locals_tp.enable
      end

      at_exit { close }
    end

    # Flushes pending events and cleans up SDK state.
    # SDK will stop sending events and all top-level APIs will be no-ops after this.
    #
    # @return [void]
    def close
      if @background_worker
        @background_worker.shutdown
        @background_worker = nil
      end

      if @session_flusher
        @session_flusher.kill
        @session_flusher = nil
      end

      if configuration&.capture_exception_frame_locals
        exception_locals_tp.disable
      end

      @main_hub = nil
      Thread.current.thread_variable_set(THREAD_LOCAL, nil)
    end

    # Returns true if the SDK is initialized.
    #
    # @return [Boolean]
    def initialized?
      !!get_main_hub
    end

    # Returns an uri for security policy reporting that's generated from the given DSN
    # (To learn more about security policy reporting: https://docs.sentry.io/product/security-policy-reporting/)
    #
    # It returns nil if
    # - The SDK is not initialized yet.
    # - The DSN is not provided or is invalid.
    #
    # @return [String, nil]
    def csp_report_uri
      return unless initialized?
      configuration.csp_report_uri
    end

    # Returns the main thread's active hub.
    #
    # @return [Hub]
    def get_main_hub
      @main_hub
    end

    # Takes an instance of Sentry::Breadcrumb and stores it to the current active scope.
    #
    # @return [Breadcrumb, nil]
    def add_breadcrumb(breadcrumb, **options)
      return unless initialized?
      get_current_hub.add_breadcrumb(breadcrumb, **options)
    end

    # Returns the current active hub.
    # If the current thread doesn't have an active hub, it will clone the main thread's active hub,
    # stores it in the current thread, and then returns it.
    #
    # @return [Hub]
    def get_current_hub
      # we need to assign a hub to the current thread if it doesn't have one yet
      #
      # ideally, we should do this proactively whenever a new thread is created
      # but it's impossible for the SDK to keep track every new thread
      # so we need to use this rather passive way to make sure the app doesn't crash
      Thread.current.thread_variable_get(THREAD_LOCAL) || clone_hub_to_current_thread
    end

    # Returns the current active client.
    # @return [Client, nil]
    def get_current_client
      return unless initialized?
      get_current_hub.current_client
    end

    # Returns the current active scope.
    #
    # @return [Scope, nil]
    def get_current_scope
      return unless initialized?
      get_current_hub.current_scope
    end

    # Clones the main thread's active hub and stores it to the current thread.
    #
    # @return [void]
    def clone_hub_to_current_thread
      return unless initialized?
      Thread.current.thread_variable_set(THREAD_LOCAL, get_main_hub.clone)
    end

    # Takes a block and yields the current active scope.
    #
    # @example
    #   Sentry.configure_scope do |scope|
    #     scope.set_tags(foo: "bar")
    #   end
    #
    #   Sentry.capture_message("test message") # this event will have tags { foo: "bar" }
    #
    # @yieldparam scope [Scope]
    # @return [void]
    def configure_scope(&block)
      return unless initialized?
      get_current_hub.configure_scope(&block)
    end

    # Takes a block and yields a temporary scope.
    # The temporary scope will inherit all the attributes from the current active scope and replace it to be the active
    # scope inside the block.
    #
    # @example
    #   Sentry.configure_scope do |scope|
    #     scope.set_tags(foo: "bar")
    #   end
    #
    #   Sentry.capture_message("test message") # this event will have tags { foo: "bar" }
    #
    #   Sentry.with_scope do |temp_scope|
    #     temp_scope.set_tags(foo: "baz")
    #     Sentry.capture_message("test message 2") # this event will have tags { foo: "baz" }
    #   end
    #
    #   Sentry.capture_message("test message 3") # this event will have tags { foo: "bar" }
    #
    # @yieldparam scope [Scope]
    # @return [void]
    def with_scope(&block)
      return yield unless initialized?
      get_current_hub.with_scope(&block)
    end

    # Wrap a given block with session tracking.
    # Aggregate sessions in minutely buckets will be recorded
    # around this block and flushed every minute.
    #
    # @example
    #   Sentry.with_session_tracking do
    #     a = 1 + 1 # new session recorded with :exited status
    #   end
    #
    #   Sentry.with_session_tracking do
    #     1 / 0
    #   rescue => e
    #     Sentry.capture_exception(e) # new session recorded with :errored status
    #   end
    # @return [void]
    def with_session_tracking(&block)
      return yield unless initialized?
      get_current_hub.with_session_tracking(&block)
    end

    # Takes an exception and reports it to Sentry via the currently active hub.
    #
    # @yieldparam scope [Scope]
    # @return [Event, nil]
    def capture_exception(exception, **options, &block)
      return unless initialized?
      get_current_hub.capture_exception(exception, **options, &block)
    end

    # Takes a block and evaluates it. If the block raised an exception, it reports the exception to Sentry and re-raises it.
    # If the block ran without exception, it returns the evaluation result.
    #
    # @example
    #   Sentry.with_exception_captured do
    #     1/1 #=> 1 will be returned
    #   end
    #
    #   Sentry.with_exception_captured do
    #     1/0 #=> ZeroDivisionError will be reported and re-raised
    #   end
    #
    def with_exception_captured(**options, &block)
      yield
    rescue Exception => e
      capture_exception(e, **options)
      raise
    end

    # Takes a message string and reports it to Sentry via the currently active hub.
    #
    # @yieldparam scope [Scope]
    # @return [Event, nil]
    def capture_message(message, **options, &block)
      return unless initialized?
      get_current_hub.capture_message(message, **options, &block)
    end

    # Takes an instance of Sentry::Event and dispatches it to the currently active hub.
    #
    # @return [Event, nil]
    def capture_event(event)
      return unless initialized?
      get_current_hub.capture_event(event)
    end

    # Takes or initializes a new Sentry::Transaction and makes a sampling decision for it.
    #
    # @return [Transaction, nil]
    def start_transaction(**options)
      return unless initialized?
      get_current_hub.start_transaction(**options)
    end

    # Records the block's execution as a child of the current span.
    # If the current scope doesn't have a span, the block would still be executed but the yield param will be nil.
    # @param attributes [Hash] attributes for the child span.
    # @yieldparam child_span [Span, nil]
    # @return yield result
    #
    # @example
    #   Sentry.with_child_span(op: "my operation") do |child_span|
    #     child_span.set_data(operation_data)
    #     child_span.set_description(operation_detail)
    #     # result will be returned
    #   end
    #
    def with_child_span(**attributes, &block)
      if Sentry.initialized? && current_span = get_current_scope.get_span
        result = nil

        begin
          current_span.with_child_span(**attributes) do |child_span|
            get_current_scope.set_span(child_span)
            result = yield(child_span)
          end
        ensure
          get_current_scope.set_span(current_span)
        end

        result
      else
        yield(nil)
      end
    end

    # Returns the id of the lastly reported Sentry::Event.
    #
    # @return [String, nil]
    def last_event_id
      return unless initialized?
      get_current_hub.last_event_id
    end

    # Checks if the exception object has been captured by the SDK.
    #
    # @return [Boolean]
    def exception_captured?(exc)
      return false unless initialized?
      !!exc.instance_variable_get(CAPTURED_SIGNATURE)
    end

    ##### Helpers #####

    # @!visibility private
    def sys_command(command)
      result = `#{command} 2>&1` rescue nil
      return if result.nil? || result.empty? || ($CHILD_STATUS && $CHILD_STATUS.exitstatus != 0)

      result.strip
    end

    # @!visibility private
    def logger
      configuration.logger
    end

    # @!visibility private
    def sdk_meta
      META
    end

    # @!visibility private
    def utc_now
      Time.now.utc
    end
  end
end

# patches
require "sentry/net/http"
require "sentry/redis"
