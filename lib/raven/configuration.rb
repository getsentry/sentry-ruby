require 'logger'
require 'uri'

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
    attr_reader :project_root

    # Encoding type for event bodies
    attr_reader :encoding

    # Logger to use internally
    attr_accessor :logger

    # Silence ready message
    attr_accessor :silence_ready

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

    # The path to the SSL certificate file
    attr_accessor :ssl_ca_file

    # SSl settings passed direactly to faraday's ssl option
    attr_accessor :ssl

    # Proxy information to pass to the HTTP adapter
    attr_accessor :proxy

    attr_reader :current_environment

    # The Faraday adapter to be used. Will default to Net::HTTP when not set.
    attr_accessor :http_adapter

    attr_accessor :server_name

    attr_accessor :release

    # DEPRECATED: This option is now ignored as we use our own adapter.
    attr_accessor :json_adapter

    # Default tags for events
    attr_accessor :tags

    # Optional Proc to be used to send events asynchronously.
    attr_reader :async

    # Optional Proc, called when the Sentry server cannot be contacted for any reason
    attr_reader :transport_failure_callback

    # Directories to be recognized as part of your app. e.g. if you
    # have an `engines` dir at the root of your project, you may want
    # to set this to something like /(app|config|engines|lib)/
    attr_accessor :app_dirs_pattern

    # Rails catches exceptions in the ActionDispatch::ShowExceptions or
    # ActionDispatch::DebugExceptions middlewares, depending on the environment.
    # When `rails_report_rescued_exceptions` is true (it is by default), Raven
    # will report exceptions even when they are rescued by these middlewares.
    attr_accessor :rails_report_rescued_exceptions
    # Deprecated accessor
    attr_reader :catch_debugged_exceptions

    # Turns on ActiveSupport breadcrumbs integration
    attr_accessor :rails_activesupport_breadcrumbs

    # Provide a configurable callback to determine event capture
    attr_accessor :should_capture

    # additional fields to sanitize
    attr_accessor :sanitize_fields

    # Sanitize values that look like credit card numbers
    attr_accessor :sanitize_credit_cards

    # Truncate any strings longer than this bytesize before sending
    attr_accessor :event_bytesize_limit

    # Logger 'progname's to exclude from breadcrumbs
    attr_accessor :exclude_loggers

    IGNORE_DEFAULT = [
      'AbstractController::ActionNotFound',
      'ActionController::InvalidAuthenticityToken',
      'ActionController::RoutingError',
      'ActionController::UnknownAction',
      'ActiveRecord::RecordNotFound',
      'CGI::Session::CookieStore::TamperedWithCookie',
      'Mongoid::Errors::DocumentNotFound',
      'Sinatra::NotFound',
    ].freeze

    DEFAULT_PROCESSORS = [
      Raven::Processor::Truncator,
      Raven::Processor::RemoveCircularReferences,
      Raven::Processor::UTF8Conversion,
      Raven::Processor::SanitizeData,
      Raven::Processor::Cookies,
      Raven::Processor::PostData,
    ].freeze

    def initialize
      self.server = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN']
      @context_lines = 3
      self.current_environment = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'default'
      self.send_modules = true
      self.excluded_exceptions = IGNORE_DEFAULT.dup
      self.processors = DEFAULT_PROCESSORS.dup
      self.ssl_verification = true
      self.encoding = 'gzip'
      self.timeout = 2
      self.open_timeout = 1
      self.proxy = nil
      self.tags = {}
      self.async = false
      self.rails_report_rescued_exceptions = true
      self.rails_activesupport_breadcrumbs = false
      self.transport_failure_callback = false
      self.sanitize_fields = []
      self.sanitize_credit_cards = true
      self.event_bytesize_limit = 8_000
      self.environments = []
      self.exclude_loggers = []

      self.release = detect_release

      # Try to resolve the hostname to an FQDN, but fall back to whatever the load name is
      self.server_name = Socket.gethostname
      self.server_name = Socket.gethostbyname(hostname).first rescue server_name
    end

    def server=(value)
      uri = URI.parse(value)
      uri_path = uri.path.split('/')

      if uri.user
        # DSN-style string
        self.project_id = uri_path.pop
        self.public_key = uri.user
        self.secret_key = uri.password
      end

      self.scheme = uri.scheme
      self.host = uri.host
      self.port = uri.port if uri.port
      self.path = uri_path.join('/')

      # For anyone who wants to read the base server string
      @server = "#{scheme}://#{host}"
      @server << ":#{port}" unless port == { 'http' => 80, 'https' => 443 }[scheme]
      @server << path
    end

    def encoding=(encoding)
      raise Error.new('Unsupported encoding') unless %w(gzip json).include? encoding
      @encoding = encoding
    end

    alias dsn= server=

    def async=(value)
      raise ArgumentError.new("async must be callable (or false to disable)") unless value == false || value.respond_to?(:call)
      @async = value
    end

    alias async? async

    def transport_failure_callback=(value)
      raise ArgumentError.new("transport_failure_callback must be callable (or false to disable)") unless value == false || value.respond_to?(:call)
      @transport_failure_callback = value
    end

    # Allows config options to be read like a hash
    #
    # @param [Symbol] option Key for a given attribute
    def [](option)
      send(option)
    end

    def current_environment=(environment)
      @current_environment = environment.to_s
    end

    def capture_allowed?(message_or_exc)
      capture_in_current_environment? &&
        capture_allowed_by_callback?(message_or_exc)
    end

    # If we cannot capture, we cannot send.
    alias sending_allowed? capture_allowed?

    def capture_in_current_environment?
      !!server && (environments.empty? || environments.include?(current_environment))
    end

    def capture_allowed_by_callback?(message_or_exc)
      return true unless should_capture
      should_capture.call(*[message_or_exc])
    end

    def verify!
      raise Error.new('No server specified') unless server
      raise Error.new('No public key specified') unless public_key
      raise Error.new('No secret key specified') unless secret_key
      raise Error.new('No project ID specified') unless project_id
    end

    def detect_release
      detect_release_from_heroku ||
        detect_release_from_capistrano ||
        detect_release_from_git
    end

    def project_root=(root_dir)
      @project_root = root_dir
      Backtrace::Line.instance_variable_set(:@in_app_pattern, nil) # blow away cache
    end

    def catch_debugged_exceptions=(boolean)
      Raven.logger.warn "DEPRECATION WARNING: catch_debugged_exceptions has been \
        renamed to rails_report_rescued_exceptions. catch_debugged_exceptions will \
        be removed in raven-ruby 0.17.0"
      self.rails_report_rescued_exceptions = boolean
    end

    private

    def detect_release_from_heroku
      ENV['HEROKU_SLUG_COMMIT']
    end

    def detect_release_from_capistrano
      version = File.read(File.join(project_root, 'REVISION')).strip rescue nil

      # Capistrano 3.0 - 3.1.x
      version || File.open(File.join(project_root, '..', 'revisions.log')).to_a.last.strip.sub(/.*as release ([0-9]+).*/, '\1') rescue nil
    end

    def detect_release_from_git
      `git rev-parse --short HEAD`.strip if File.directory?(".git") rescue nil
    end
  end
end
