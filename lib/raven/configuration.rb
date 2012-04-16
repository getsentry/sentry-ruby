module Raven
  class Configuration

    # Base URL of the Sentry server
    attr_accessor :server

    # Public key for authentication with the Sentry server
    attr_accessor :public_key

    # Secret key for authentication with the Sentry server
    attr_accessor :secret_key

    # Project ID number to send to the Sentry server
    attr_accessor :project_id

    # Logger to use internally
    attr_accessor :logger

    def initialize
      self.server = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN']
    end

    def server=(value)
      uri = URI::parse(value)
      if uri.user
        # DSN-style string
        uri_path = uri.path.split('/')
        @project_id = uri_path.pop
        @server = "#{uri.scheme}://#{uri.host}"
        @server << ":#{uri.port}" unless uri.port == {'http'=>80,'https'=>443}[uri.scheme]
        @server << uri_path.join('/')
        @public_key = uri.user
        @secret_key = uri.password
      else
        @server = value
      end
    end

    alias_method :dsn=, :server=

    # Allows config options to be read like a hash
    #
    # @param [Symbol] option Key for a given attribute
    def [](option)
      send(option)
    end

  end
end
