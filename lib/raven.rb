require 'raven/version'
require 'raven/configuration'
require 'raven/logger'
require 'raven/client'
require 'raven/event'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/stack_trace'

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
      self.sender = Sender.new(configuration)
      report_ready unless silent
      self.sender
    end

  end
end
