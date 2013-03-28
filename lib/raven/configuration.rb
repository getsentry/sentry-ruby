module Raven
  class Configuration

    # Simple server string (setter provided below)
    attr_reader :server

    # Public key for authentication with the Sentry server
    attr_accessor :public_key

    # Secret key for authentication with the Sentry server
    attr_accessor :secret_key

    # Accessors for the component parts of the DSN
    attr_accessor :scheme
    attr_accessor :host
    attr_accessor :port
    attr_accessor :path

    # Project ID number to send to the Sentry server
    attr_accessor :project_id

    # Project directory root
    attr_accessor :project_root

    # Encoding type for event bodies
    attr_reader :encoding

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

    # Timeout when waiting for the server to return data in seconds
    attr_accessor :timeout

    # Timeout waiting for the connection to open in seconds
    attr_accessor :open_timeout

    # Should the SSL certificate of the server be verified?
    attr_accessor :ssl_verification

    attr_reader :current_environment

    # The Faraday adapter to be used. Will default to Net::HTTP when not set.
    attr_accessor :http_adapter

    attr_accessor :server_name

    # request.env params to include in Environment
    attr_accessor :extra_request_vars

    IGNORE_DEFAULT = ['ActiveRecord::RecordNotFound',
                      'ActionController::RoutingError',
                      'ActionController::InvalidAuthenticityToken',
                      'CGI::Session::CookieStore::TamperedWithCookie',
                      'ActionController::UnknownAction',
                      'AbstractController::ActionNotFound',
                      'Mongoid::Errors::DocumentNotFound']

    def initialize
      self.server = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN']
      @context_lines = 3
      self.environments = %w[ production ]
      self.current_environment = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
      self.send_modules = true
      self.excluded_exceptions = IGNORE_DEFAULT
      self.processors = [Raven::Processor::SanitizeData]
      self.ssl_verification = true
      self.encoding = 'json'
      self.timeout = 1
      self.open_timeout = 1
      self.extra_request_vars = []
    end

    def server=(value)
      uri = URI::parse(value)
      uri_path = uri.path.split('/')

      if uri.user
        # DSN-style string
        @project_id = uri_path.pop
        @public_key = uri.user
        @secret_key = uri.password
      end

      @scheme = uri.scheme
      @host = uri.host
      @port = uri.port if uri.port
      @path = uri_path.join('/')

      # For anyone who wants to read the base server string
      @server = "#{@scheme}://#{@host}"
      @server << ":#{@port}" unless @port == {'http'=>80,'https'=>443}[@scheme]
      @server << @path
    end

    def encoding=(encoding)
      raise Error.new('Unsupported encoding') unless ['gzip', 'json'].include? encoding
      @encoding = encoding
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
