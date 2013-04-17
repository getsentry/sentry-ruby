require 'raven/version'
require 'raven/backtrace'
require 'raven/configuration'
require 'raven/context'
require 'raven/client'
require 'raven/event'
require 'raven/logger'
require 'raven/rack'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/stack_trace'
require 'raven/interfaces/http'
require 'raven/processors/sanitizedata'

require 'raven/railtie' if defined?(Rails::Railtie)
require 'raven/sidekiq' if defined?(Sidekiq)


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
      if block_given?
        yield(configuration)
      end

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
    def capture(options={}, &block)
      if block
        begin
          block.call
        rescue Error => e
          raise # Don't capture Raven errors
        rescue Exception => e
          capture_exception(e, options)
          raise
        end
      else
        # Install at_exit hook
        at_exit do
          if $!
            logger.debug "Caught a post-mortem exception: #{$!.inspect}"
            capture_exception($!, options)
          end
        end
      end
    end

    def capture_exception(exception, options={})
      if evt = Event.capture_exception(exception, options)
        yield evt if block_given?
        send(evt)
      end
    end

    def capture_message(message, options={})
      if evt = Event.capture_message(message, options)
        yield evt if block_given?
        send(evt)
      end
    end

    # Bind user context. Merges with existing context (if any).
    #
    # It is recommending that you send at least the ``id`` and ``email``
    # values. All other values are arbitrary.
    #
    # @example
    #   Raven.user_context('id' => 1, 'email' => 'foo@example.com')
    def user_context(options={})
      self.context.user.merge!(options)
    end

    # Bind tags context. Merges with existing context (if any).
    #
    # Tags are key / value pairs which generally represent things like application version,
    # environment, role, and server names.
    #
    # @example
    #   Raven.tags_context('my_custom_tag' => 'tag_value')
    def tags_context(options={})
      self.context.tags.merge!(options)
    end

    # Bind extra context. Merges with existing context (if any).
    #
    # Extra context shows up as Additional Data within Sentry, and is completely arbitrary.
    #
    # @example
    #   Raven.tags_context('my_custom_data' => 'value')
    def extra_context(options={})
      self.context.extra.merge!(options)
    end

    # For cross-language compat
    alias :captureException :capture_exception
    alias :captureMessage :capture_message
  end
end
