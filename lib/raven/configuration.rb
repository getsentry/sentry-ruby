require 'uri'

module Raven
  class Configuration
    # Directories to be recognized as part of your app. e.g. if you
    # have an `engines` dir at the root of your project, you may want
    # to set this to something like /(app|config|engines|lib)/
    attr_accessor :app_dirs_pattern

    # Provide an object that responds to `call` to send events asynchronously.
    # E.g.: lambda { |event| Thread.new { Raven.send_event(event) } }
    attr_reader :async
    alias async? async

    # Number of lines of code context to capture, or nil for none
    attr_accessor :context_lines

    # RACK_ENV by default.
    attr_reader :current_environment

    # Encoding type for event bodies. Must be :json or :gzip.
    attr_reader :encoding

    # Whitelist of environments that will send notifications to Sentry. Array of Strings.
    attr_accessor :environments

    # Logger 'progname's to exclude from breadcrumbs
    attr_accessor :exclude_loggers

    # Array of exception classes that should never be sent. See IGNORE_DEFAULT.
    # You should probably append to this rather than overwrite it.
    attr_accessor :excluded_exceptions

    # DSN component - set automatically if DSN provided
    attr_accessor :host

    # The Faraday adapter to be used. Will default to Net::HTTP when not set.
    attr_accessor :http_adapter

    # A Proc yeilding the faraday builder allowing for further configuration
    # of the faraday adapter
    attr_accessor :faraday_builder

    # You may provide your own LineCache for matching paths with source files.
    # This may be useful if you need to get source code from places other than
    # the disk. See Raven::LineCache for the required interface you must implement.
    attr_accessor :linecache

    # Logger used by Raven. In Rails, this is the Rails logger, otherwise
    # Raven provides its own Raven::Logger.
    attr_accessor :logger

    # Timeout waiting for the Sentry server connection to open in seconds
    attr_accessor :open_timeout

    # DSN component - set automatically if DSN provided
    attr_accessor :path

    # DSN component - set automatically if DSN provided
    attr_accessor :port

    # Processors to run on data before sending upstream. See DEFAULT_PROCESSORS.
    # You should probably append to this rather than overwrite it.
    attr_accessor :processors

    # Project ID number to send to the Sentry server
    # If you provide a DSN, this will be set automatically.
    attr_accessor :project_id

    # Project directory root for in_app detection. Could be Rails root, etc.
    # Set automatically for Rails.
    attr_reader :project_root

    # Proxy information to pass to the HTTP adapter (via Faraday)
    attr_accessor :proxy

    # Public key for authentication with the Sentry server
    # If you provide a DSN, this will be set automatically.
    attr_accessor :public_key

    # Turns on ActiveSupport breadcrumbs integration
    attr_accessor :rails_activesupport_breadcrumbs

    # Rails catches exceptions in the ActionDispatch::ShowExceptions or
    # ActionDispatch::DebugExceptions middlewares, depending on the environment.
    # When `rails_report_rescued_exceptions` is true (it is by default), Raven
    # will report exceptions even when they are rescued by these middlewares.
    attr_accessor :rails_report_rescued_exceptions

    # Release tag to be passed with every event sent to Sentry.
    # We automatically try to set this to a git SHA or Capistrano release.
    attr_accessor :release

    # Boolean - sanitize values that look like credit card numbers
    attr_accessor :sanitize_credit_cards

    # By default, Sentry censors Hash values when their keys match things like
    # "secret", "password", etc. Provide an array of Strings that, when matched in
    # a hash key, will be censored and not sent to Sentry.
    attr_accessor :sanitize_fields

    # Sanitize additional HTTP headers - only Authorization is removed by default.
    attr_accessor :sanitize_http_headers

    # DSN component - set automatically if DSN provided.
    # Otherwise, can be one of "http", "https", or "dummy"
    attr_accessor :scheme

    # Secret key for authentication with the Sentry server
    # If you provide a DSN, this will be set automatically.
    attr_accessor :secret_key

    # Include module versions in reports - boolean.
    attr_accessor :send_modules

    # Simple server string - set this to the DSN found on your Sentry settings.
    attr_reader :server

    attr_accessor :server_name

    # Provide a configurable callback to determine event capture.
    # Note that the object passed into the block will be a String (messages) or
    # an exception.
    # e.g. lambda { |exc_or_msg| exc_or_msg.some_attr == false }
    attr_accessor :should_capture

    # Silences ready message when true.
    attr_accessor :silence_ready

    # SSL settings passed directly to Faraday's ssl option
    attr_accessor :ssl

    # The path to the SSL certificate file
    attr_accessor :ssl_ca_file

    # Should the SSL certificate of the server be verified?
    attr_accessor :ssl_verification

    # Default tags for events. Hash.
    attr_accessor :tags

    # Timeout when waiting for the server to return data in seconds.
    attr_accessor :timeout

    # Optional Proc, called when the Sentry server cannot be contacted for any reason
    # E.g. lambda { |event| Thread.new { MyJobProcessor.send_email(event) } }
    attr_reader :transport_failure_callback

    # Errors object - an Array that contains error messages. See #
    attr_reader :errors

    IGNORE_DEFAULT = [
      'AbstractController::ActionNotFound',
      'ActionController::InvalidAuthenticityToken',
      'ActionController::RoutingError',
      'ActionController::UnknownAction',
      'ActiveRecord::RecordNotFound',
      'CGI::Session::CookieStore::TamperedWithCookie',
      'Mongoid::Errors::DocumentNotFound',
      'Sinatra::NotFound'
    ].freeze

    # Note the order - we have to remove circular references and bad characters
    # before passing to other processors.
    DEFAULT_PROCESSORS = [
      Raven::Processor::RemoveCircularReferences,
      Raven::Processor::UTF8Conversion,
      Raven::Processor::SanitizeData,
      Raven::Processor::Cookies,
      Raven::Processor::PostData,
      Raven::Processor::HTTPHeaders
    ].freeze

    LOG_PREFIX = "** [Raven] ".freeze

    def initialize
      self.async = false
      self.context_lines = 3
      self.current_environment = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'default'
      self.encoding = 'gzip'
      self.environments = []
      self.exclude_loggers = []
      self.excluded_exceptions = IGNORE_DEFAULT.dup
      self.linecache = ::Raven::LineCache.new
      self.logger = ::Raven::Logger.new(STDOUT)
      self.open_timeout = 1
      self.processors = DEFAULT_PROCESSORS.dup
      self.proxy = nil
      self.rails_activesupport_breadcrumbs = false
      self.rails_report_rescued_exceptions = true
      self.release = detect_release
      self.sanitize_credit_cards = true
      self.sanitize_fields = []
      self.sanitize_http_headers = []
      self.send_modules = true
      self.server = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN']
      self.server_name = resolve_hostname
      self.should_capture = false
      self.ssl_verification = true
      self.tags = {}
      self.timeout = 2
      self.transport_failure_callback = false
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
    alias dsn= server=

    def encoding=(encoding)
      raise(Error, 'Unsupported encoding') unless %w(gzip json).include? encoding
      @encoding = encoding
    end

    def async=(value)
      unless value == false || value.respond_to?(:call)
        raise(ArgumentError, "async must be callable (or false to disable)")
      end
      @async = value
    end

    def transport_failure_callback=(value)
      unless value == false || value.respond_to?(:call)
        raise(ArgumentError, "transport_failure_callback must be callable (or false to disable)")
      end
      @transport_failure_callback = value
    end

    def should_capture=(value)
      unless value == false || value.respond_to?(:call)
        raise ArgumentError, "should_capture must be callable (or false to disable)"
      end
      @should_capture = value
    end

    # Allows config options to be read like a hash
    #
    # @param [Symbol] option Key for a given attribute
    def [](option)
      public_send(option)
    end

    def current_environment=(environment)
      @current_environment = environment.to_s
    end

    def capture_allowed?(message_or_exc = nil)
      @errors = []

      valid? &&
        capture_in_current_environment? &&
        capture_allowed_by_callback?(message_or_exc)
    end
    # If we cannot capture, we cannot send.
    alias sending_allowed? capture_allowed?

    def error_messages
      @errors = [errors[0]] + errors[1..-1].map(&:downcase) # fix case of all but first
      errors.join(", ")
    end

    def project_root=(root_dir)
      @project_root = root_dir
      Backtrace::Line.instance_variable_set(:@in_app_pattern, nil) # blow away cache
    end

    def detect_release
      detect_release_from_git ||
        detect_release_from_capistrano ||
        detect_release_from_heroku
    end

    private

    def detect_release_from_heroku
      sys_dyno_info = File.read("/etc/heroku/dyno").strip if File.directory?("/etc/heroku") rescue nil
      return unless sys_dyno_info

      # being overly cautious, because if we raise an error Raven won't start
      begin
        hash = JSON.parse(sys_dyno_info)
        hash && hash["release"] && hash["release"]["commit"]
      rescue JSON::JSONError
        logger.error "Cannot parse Heroku JSON: #{sys_dyno_info}"
      end
    end

    def detect_release_from_capistrano
      version = File.read(File.join(project_root, 'REVISION')).strip rescue nil

      # Capistrano 3.0 - 3.1.x
      version || File.open(File.join(project_root, '..', 'revisions.log')).to_a.last.strip.sub(/.*as release ([0-9]+).*/, '\1') rescue nil
    end

    def detect_release_from_git
      `git rev-parse --short HEAD`.strip if File.directory?(".git") rescue nil
    end

    def capture_in_current_environment?
      return true unless environments.any? && !environments.include?(current_environment)
      @errors << "Not configured to send/capture in environment '#{current_environment}'"
      false
    end

    def capture_allowed_by_callback?(message_or_exc)
      return true if !should_capture || message_or_exc.nil? || should_capture.call(*[message_or_exc])
      @errors << "should_capture returned false"
      false
    end

    def valid?
      return true if %w(server host path public_key secret_key project_id).all? { |k| public_send(k) }
      if server
        %w(server host path public_key secret_key project_id).map do |key|
          @errors << "No #{key} specified" unless public_send(key)
        end
      else
        @errors << "DSN not set"
      end
      false
    end

    # Try to resolve the hostname to an FQDN, but fall back to whatever
    # the load name is.
    def resolve_hostname
      Socket.gethostname ||
        Socket.gethostbyname(hostname).first rescue server_name
    end
  end
end
