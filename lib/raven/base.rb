require 'raven/version'
require 'raven/backtrace'
require 'raven/configuration'
require 'raven/context'
require 'raven/client'
require 'raven/event'
require 'raven/logger'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/single_exception'
require 'raven/interfaces/stack_trace'
require 'raven/interfaces/http'
require 'raven/processor'
require 'raven/processor/sanitizedata'
require 'raven/processor/removecircularreferences'
require 'raven/processor/utf8conversion'

if RUBY_VERSION >= '1.9.2' && !defined?(JRUBY_VERSION)
  require 'binding_of_caller'
  require 'thread'
end

major, minor, patch = RUBY_VERSION.split('.').map(&:to_i)
if (major == 1 && minor < 9) || (major == 1 && minor == 9 && patch < 2)
  require 'raven/backports/uri'
end

module Kernel
  def self.monkey_patch_raise
    return false if RUBY_VERSION < '1.9.2' || defined?(JRUBY_VERSION)

    if @@monkey_patch_raise_occur == true
      return
    end

    @@monkey_patch_raise_mutex.synchronize {
      return if @@monkey_patch_raise_occur == true

      apply_monkey_patch_raise
      @@monkey_patch_raise_occur = true
    }
  end

  def self.monkey_patch_raise_rollback
    return if @@monkey_patch_raise_occur == false

    @@monkey_patch_raise_mutex.synchronize {
      return if @@monkey_patch_raise_occur == false
      return if @@original_raise.nil?

      define_method(:raise) do |*args|
        @@original_raise.call(*args)
      end
      @@monkey_patch_raise_occur = false
    }
  end

  def self.monkey_patch_raise_occur
    @@monkey_patch_raise_occur
  end

  def self.monkey_patch_original_raise
    @@original_raise
  end

  private
  def self.apply_monkey_patch_raise
    @@original_raise = method(:raise)

    define_method(:raise) do |*args|
      begin
        @@original_raise.call(*args)
      rescue Exception => e
        prev_stack_info = e.instance_variable_get(:@stack_info)
        if prev_stack_info.nil?
          line_backtrace = Raven::Backtrace::Line.parse(e.backtrace[0])
          if line_backtrace.file == __FILE__
            pop_length = 2
          else
            pop_length = 0
          end

          callers = binding.callers.drop(pop_length)
          e.instance_variable_set(:@stack_info, callers)
          e.set_backtrace(e.backtrace.drop(pop_length))

          callers.each_with_index do |caller_obj, idx|
            e.backtrace[idx].instance_variable_set(:@stack_info, caller_obj)
          end
        end
        @@original_raise.call(e)
      end
    end
  end

  @@monkey_patch_raise_occur = false
  @@monkey_patch_raise_mutex = Mutex.new
  @@original_raise = nil
end

module Raven
  class << self
    # The client object is responsible for delivering formatted data to the Sentry server.
    # Must respond to #send. See Raven::Client.
    attr_writer :client

    # A Raven configuration object. Must act like a hash and return sensible
    # values for all Raven configuration options. See Raven::Configuration.
    attr_writer :configuration

    def context
      Context.current
    end

    def logger
      @logger ||= Logger.new
    end

    # The configuration object.
    # @see Raven.configure
    def configuration
      @configuration ||= Configuration.new
    end

    # The client object is responsible for delivering formatted data to the Sentry server.
    def client
      @client ||= Client.new(configuration)
    end

    # Tell the log that the client is good to go
    def report_status
      return if client.configuration.silence_ready
      if client.configuration.send_in_current_environment?
        logger.info "Raven #{VERSION} ready to catch errors"
      else
        logger.info "Raven #{VERSION} configured not to send errors."
      end
    end
    alias_method :report_ready, :report_status

    # Call this method to modify defaults in your initializers.
    #
    # @example
    #   Raven.configure do |config|
    #     config.server = 'http://...'
    #   end
    def configure
      yield(configuration) if block_given?

      self.client = Client.new(configuration)
      report_status
      self.client
    end

    # Send an event to the configured Sentry server
    #
    # @example
    #   evt = Raven::Event.new(:message => "An error")
    #   Raven.send_event(evt)
    def send_event(event)
      client.send_event(event)
    end

    def send(event)
      Raven.logger.warn "DEPRECATION WARNING: Calling #send on Raven::Base will be \
        removed in Raven-Ruby 0.14! Use #send_event instead!"
      client.send_event(event)
    end

    # Capture and process any exceptions from the given block, or globally if
    # no block is given
    #
    # @example
    #   Raven.capture do
    #     MyApp.run
    #   end
    def capture(options = {})
      if block_given?
        begin
          yield
        rescue Error
          raise # Don't capture Raven errors
        rescue Exception => e
          capture_exception(e, options)
          raise
        end
      else
        install_at_exit_hook(options)
      end
    end

    def capture_type(obj, options = {})
      return false unless should_capture?(obj)
      message_or_exc = obj.is_a?(String) ? "message" : "exception"
      if (evt = Event.send("from_" + message_or_exc, obj, options))
        yield evt if block_given?
        if configuration.async?
          configuration.async.call(evt)
        else
          send_event(evt)
        end
      end
    end
    alias_method :capture_message, :capture_type
    alias_method :capture_exception, :capture_type

    def should_capture?(message_or_exc)
      if configuration.should_capture
        configuration.should_capture.call(*[message_or_exc])
      else
        true
      end
    end

    # Provides extra context to the exception prior to it being handled by
    # Raven. An exception can have multiple annotations, which are merged
    # together.
    #
    # The options (annotation) is treated the same as the ``options``
    # parameter to ``capture_exception`` or ``Event.from_exception``, and
    # can contain the same ``:user``, ``:tags``, etc. options as these
    # methods.
    #
    # These will be merged with the ``options`` parameter to
    # ``Event.from_exception`` at the top of execution.
    #
    # @example
    #   begin
    #     raise "Hello"
    #   rescue => exc
    #     Raven.annotate_exception(exc, :user => { 'id' => 1,
    #                              'email' => 'foo@example.com' })
    #   end
    def annotate_exception(exc, options = {})
      notes = exc.instance_variable_get(:@__raven_context) || {}
      notes.merge!(options)
      exc.instance_variable_set(:@__raven_context, notes)
      exc
    end

    # Bind user context. Merges with existing context (if any).
    #
    # It is recommending that you send at least the ``id`` and ``email``
    # values. All other values are arbitrary.
    #
    # @example
    #   Raven.user_context('id' => 1, 'email' => 'foo@example.com')
    def user_context(options = {})
      self.context.user = options
    end

    # Bind tags context. Merges with existing context (if any).
    #
    # Tags are key / value pairs which generally represent things like application version,
    # environment, role, and server names.
    #
    # @example
    #   Raven.tags_context('my_custom_tag' => 'tag_value')
    def tags_context(options = {})
      self.context.tags.merge!(options)
    end

    # Bind extra context. Merges with existing context (if any).
    #
    # Extra context shows up as Additional Data within Sentry, and is completely arbitrary.
    #
    # @example
    #   Raven.extra_context('my_custom_data' => 'value')
    def extra_context(options = {})
      self.context.extra.merge!(options)
    end

    def rack_context(env)
      if env.empty?
        env = nil
      end
      self.context.rack_env = env
    end

    # Injects various integrations
    def inject
      available_integrations = %w[delayed_job railties sidekiq rack rake]
      integrations_to_load = available_integrations & Gem.loaded_specs.keys
      # TODO(dcramer): integrations should have some additional checks baked-in
      # or we should break them out into their own repos. Specifically both the
      # rails and delayed_job checks are not always valid (i.e. Rails 2.3) and
      # https://github.com/getsentry/raven-ruby/issues/180
      integrations_to_load.each do |integration|
        begin
          require "raven/integrations/#{integration}"
        rescue Exception => error
          self.logger.warn "Unable to load raven/integrations/#{integration}: #{error}"
        end
      end
    end

    # For cross-language compat
    alias :captureException :capture_exception
    alias :captureMessage :capture_message
    alias :annotateException :annotate_exception
    alias :annotate :annotate_exception

    private

    def install_at_exit_hook(options)
      at_exit do
        if $ERROR_INFO
          logger.debug "Caught a post-mortem exception: #{$ERROR_INFO.inspect}"
          capture_exception($ERROR_INFO, options)
        end
      end
    end
  end
end
