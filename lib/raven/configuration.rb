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

    # Number of lines of code context to capture, or nil for none
    attr_accessor :context_lines

    # Whitelist of environments that will send notifications to Sentry
    attr_accessor :environments

    # Include module versions in reports?
    attr_accessor :send_modules

    # Which exceptions should never be sent
    attr_accessor :excluded_exceptions

    # Processors to run on data before sending upstream
    attr_accessor :processors

    attr_reader :current_environment

    def initialize
      self.server = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN']
      @context_lines = 3
      self.environments = %w[ production ]
      self.current_environment = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
      self.send_modules = true
      self.excluded_exceptions = []
      self.processors = [Raven::Processor::SanitizeData]
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

    def current_environment=(environment)
      @current_environment = environment.to_s
    end

    def send_in_current_environment?
      environments.include? current_environment
    end

  end
end
