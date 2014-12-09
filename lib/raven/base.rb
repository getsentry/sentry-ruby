require 'raven/version'
require 'raven/backtrace'
require 'raven/configuration'
require 'raven/context'
require 'raven/client'
require 'raven/event'
require 'raven/logger'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/stack_trace'
require 'raven/interfaces/http'
require 'raven/processor'
require 'raven/processor/sanitizedata'
require 'raven/processor/removecircularreferences'
require 'raven/processor/utf8conversion'

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
    def report_ready
      self.logger.info "Raven #{VERSION} ready to catch errors"
    end

    # Call this method to modify defaults in your initializers.
    #
    # @example
    #   Raven.configure do |config|
    #     config.server = 'http://...'
    #   end
    def configure(silent = false)
      yield(configuration) if block_given?

      self.client = Client.new(configuration)
      report_ready unless silent
      self.client
    end

    # Send an event to the configured Sentry server
    #
    # @example
    #   evt = Raven::Event.new(:message => "An error")
    #   Raven.send(evt)
    def send(evt)
      client.send(evt)
    end

    # Capture and process any exceptions from the given block, or globally if
    # no block is given
    #
    # @example
    #   Raven.capture do
    #     MyApp.run
    #   end
    def capture(options = {}, &block)
      if block
        begin
          block.call
        rescue Error
          raise # Don't capture Raven errors
        rescue Exception => e
          capture_exception(e, options)
          raise
        end
      else
        # Install at_exit hook
        at_exit do
          if $ERROR_INFO
            logger.debug "Caught a post-mortem exception: #{$ERROR_INFO.inspect}"
            capture_exception($ERROR_INFO, options)
          end
        end
      end
    end

    def capture_exception(exception, options = {})
      send_or_skip(exception) do
        if (evt = Event.from_exception(exception, options))
          yield evt if block_given?
          if configuration.async?
            configuration.async.call(evt)
          else
            send(evt)
          end
        end
      end
    end

    def capture_message(message, options = {})
      send_or_skip(message) do
        if (evt = Event.from_message(message, options))
          yield evt if block_given?
          if configuration.async?
            configuration.async.call(evt)
          else
            send(evt)
          end
        end
      end
    end

    def send_or_skip(exc)
      should_send = if configuration.should_send
        configuration.should_send.call(*[exc])
      else
        true
      end

      if configuration.send_in_current_environment? && should_send
        yield if block_given?
      else
        configuration.log_excluded_environment_message
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
    #   Raven.tags_context('my_custom_data' => 'value')
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
      available_integrations = %w[delayed_job rails sidekiq rack rake]
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
  end
end
