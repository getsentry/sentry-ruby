require 'raven/version'
require 'raven/configuration'
require 'raven/logger'
require 'raven/client'
require 'raven/event'
require 'raven/rack'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/stack_trace'
require 'raven/interfaces/http'
require 'raven/processors/sanitizedata'

require 'raven/railtie' if defined?(Rails::Railtie)

module Raven
  class << self
    # The client object is responsible for delivering formatted data to the Sentry server.
    # Must respond to #send. See Raven::Client.
    attr_accessor :client

    # A Raven configuration object. Must act like a hash and return sensible
    # values for all Raven configuration options. See Raven::Configuration.
    attr_writer :configuration

    def logger
      @logger ||= Logger.new
    end

    # Tell the log that the client is good to go
    def report_ready
      self.logger.info "Raven #{VERSION} ready to catch errors"
    end

    # The configuration object.
    # @see Raven.configure
    def configuration
      @configuration ||= Configuration.new
    end

    # Call this method to modify defaults in your initializers.
    #
    # @example
    #   Raven.configure do |config|
    #     config.server = 'http://...'
    #   end
    def configure(silent = false)
      yield(configuration)
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
      @client.send(evt) if @client
    end

    # Capture and process any exceptions from the given block, or globally if
    # no block is given
    #
    # @example
    #   Raven.capture do
    #     MyApp.run
    #   end
    def capture(&block)
      if block
        begin
          block.call
        rescue Error => e
          raise # Don't capture Raven errors
        rescue Exception => e
          self.captureException(e)
          raise
        end
      else
        # Install at_exit hook
        at_exit do
          if $!
            logger.debug "Caught a post-mortem exception: #{$!.inspect}"
            self.captureException($!)
          end
        end
      end
    end

    def captureException(exception)
      evt = Event.capture_exception(exception)
      send(evt) if evt
    end

    def captureMessage(message)
      evt = Event.capture_message(message)
      send(evt) if evt
    end

  end
end
