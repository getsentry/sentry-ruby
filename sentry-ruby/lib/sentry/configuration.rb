require "uri"
require "sentry/utils/exception_cause_chain"

module Sentry
  class Configuration
    # Directories to be recognized as part of your app. e.g. if you
    # have an `engines` dir at the root of your project, you may want
    # to set this to something like /(app|config|engines|lib)/
    attr_accessor :app_dirs_pattern

    # Provide an object that responds to `call` to send events asynchronously.
    # E.g.: lambda { |event| Thread.new { Sentry.send_event(event) } }
    attr_reader :async
    alias async? async

    # An array of breadcrumbs loggers to be used. Available options are:
    # - :sentry_logger
    # - :active_support_logger
    attr_reader :breadcrumbs_logger

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

    # Boolean to check nested exceptions when deciding if to exclude. Defaults to false
    attr_accessor :inspect_exception_causes_for_exclusion
    alias inspect_exception_causes_for_exclusion? inspect_exception_causes_for_exclusion

    # DSN component - set automatically if DSN provided
    attr_accessor :host

    # The Faraday adapter to be used. Will default to Net::HTTP when not set.
    attr_accessor :http_adapter

    # A Proc yeilding the faraday builder allowing for further configuration
    # of the faraday adapter
    attr_accessor :faraday_builder

    # Logger used by Sentry. In Rails, this is the Rails logger, otherwise
    # Sentry provides its own Sentry::Logger.
    attr_accessor :logger

    # Timeout waiting for the Sentry server connection to open in seconds
    attr_accessor :open_timeout

    # DSN component - set automatically if DSN provided
    attr_accessor :path

    # DSN component - set automatically if DSN provided
    attr_accessor :port

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
    attr_reader :rails_activesupport_breadcrumbs

    # Rails catches exceptions in the ActionDispatch::ShowExceptions or
    # ActionDispatch::DebugExceptions middlewares, depending on the environment.
    # When `rails_report_rescued_exceptions` is true (it is by default), Sentry
    # will report exceptions even when they are rescued by these middlewares.
    attr_accessor :rails_report_rescued_exceptions

    # Release tag to be passed with every event sent to Sentry.
    # We automatically try to set this to a git SHA or Capistrano release.
    attr_accessor :release

    # The sampling factor to apply to events. A value of 0.0 will not send
    # any events, and a value of 1.0 will send 100% of events.
    attr_accessor :sample_rate

    # Boolean - sanitize values that look like credit card numbers
    attr_accessor :sanitize_credit_cards

    # By default, Sentry censors Hash values when their keys match things like
    # "secret", "password", etc. Provide an array of Strings that, when matched in
    # a hash key, will be censored and not sent to Sentry.
    attr_accessor :sanitize_fields

    # If you're sure you want to override the default sanitization values, you can
    # add to them to an array of Strings here, e.g. %w(authorization password)
    attr_accessor :sanitize_fields_excluded

    # Sanitize additional HTTP headers - only Authorization is removed by default.
    attr_accessor :sanitize_http_headers

    # DSN component - set automatically if DSN provided.
    # Otherwise, can be one of "http", "https", or "dummy"
    attr_accessor :scheme

    # a proc/lambda that takes an array of stack traces
    # it'll be used to silence (reduce) backtrace of the exception
    #
    # for example:
    #
    # ```ruby
    # Sentry.configuration.backtrace_cleanup_callback = lambda do |backtrace|
    #   Rails.backtrace_cleaner.clean(backtrace)
    # end
    # ```
    #
    attr_accessor :backtrace_cleanup_callback

    # Secret key for authentication with the Sentry server
    # If you provide a DSN, this will be set automatically.
    #
    # This is deprecated and not necessary for newer Sentry installations any more.
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
    attr_reader :should_capture

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

    # Optional Proc, called before sending an event to the server/
    # E.g.: lambda { |event, hint| event }
    # E.g.: lambda { |event, hint| nil }
    # E.g.: lambda { |event, hint|
    #   event[:message] = 'a'
    #   event
    # }
    attr_reader :before_send

    # Errors object - an Array that contains error messages. See #
    attr_reader :errors

    # the dsn value, whether it's set via `config.dsn=` or `ENV["SENTRY_DSN"]`
    attr_reader :dsn

    # Most of these errors generate 4XX responses. In general, Sentry clients
    # only automatically report 5xx responses.
    IGNORE_DEFAULT = [
      'AbstractController::ActionNotFound',
      'ActionController::BadRequest',
      'ActionController::InvalidAuthenticityToken',
      'ActionController::InvalidCrossOriginRequest',
      'ActionController::MethodNotAllowed',
      'ActionController::NotImplemented',
      'ActionController::ParameterMissing',
      'ActionController::RoutingError',
      'ActionController::UnknownAction',
      'ActionController::UnknownFormat',
      'ActionController::UnknownHttpMethod',
      'ActionDispatch::Http::Parameters::ParseError',
      'ActionView::MissingTemplate',
      'ActiveJob::DeserializationError', # Can cause infinite loops
      'ActiveRecord::RecordNotFound',
      'CGI::Session::CookieStore::TamperedWithCookie',
      'Mongoid::Errors::DocumentNotFound',
      'Rack::QueryParser::InvalidParameterError',
      'Rack::QueryParser::ParameterTypeError',
      'Sinatra::NotFound'
    ].freeze

    HEROKU_DYNO_METADATA_MESSAGE = "You are running on Heroku but haven't enabled Dyno Metadata. For Sentry's "\
    "release detection to work correctly, please run `heroku labs:enable runtime-dyno-metadata`".freeze

    LOG_PREFIX = "** [Sentry] ".freeze
    MODULE_SEPARATOR = "::".freeze

    AVAILABLE_BREADCRUMBS_LOGGERS = [:sentry_logger, :active_support_logger].freeze

    def initialize
      self.async = false
      self.breadcrumbs_logger = []
      self.context_lines = 3
      self.current_environment = current_environment_from_env
      self.encoding = 'gzip'
      self.environments = []
      self.exclude_loggers = []
      self.excluded_exceptions = IGNORE_DEFAULT.dup
      self.inspect_exception_causes_for_exclusion = false
      self.logger = ::Sentry::Logger.new(STDOUT)
      self.open_timeout = 1
      self.project_root = detect_project_root
      @rails_activesupport_breadcrumbs = false

      self.rails_report_rescued_exceptions = true
      self.release = detect_release
      self.sample_rate = 1.0
      self.sanitize_credit_cards = true
      self.sanitize_fields = []
      self.sanitize_fields_excluded = []
      self.sanitize_http_headers = []
      self.send_modules = true
      self.server = ENV['SENTRY_DSN']
      self.server_name = server_name_from_env
      self.should_capture = false
      self.ssl_verification = true
      self.tags = {}
      self.timeout = 2
      self.transport_failure_callback = false
      self.before_send = false
    end

    def server=(value)
      return if value.nil?

      @dsn = value

      uri = URI.parse(value)
      uri_path = uri.path.split('/')

      if uri.user
        # DSN-style string
        self.project_id = uri_path.pop
        self.public_key = uri.user
        self.secret_key = !(uri.password.nil? || uri.password.empty?) ? uri.password : nil
      end

      self.scheme = uri.scheme
      self.host = uri.host
      self.port = uri.port if uri.port
      self.path = uri_path.join('/')

      # For anyone who wants to read the base server string
      @server = "#{scheme}://#{host}"
      @server += ":#{port}" unless port == { 'http' => 80, 'https' => 443 }[scheme]
      @server += path
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

    def breadcrumbs_logger=(logger)
      loggers =
        if logger.is_a?(Array)
          logger
        else
          unless AVAILABLE_BREADCRUMBS_LOGGERS.include?(logger)
            raise Sentry::Error, "Unsupported breadcrumbs logger. Supported loggers: #{AVAILABLE_BREADCRUMBS_LOGGERS}"
          end

          Array(logger)
        end

      require "raven/breadcrumbs/sentry_logger" if loggers.include?(:sentry_logger)

      @breadcrumbs_logger = logger
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

    def before_send=(value)
      unless value == false || value.respond_to?(:call)
        raise ArgumentError, "before_send must be callable (or false to disable)"
      end

      @before_send = value
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
        capture_allowed_by_callback?(message_or_exc) &&
        sample_allowed?
    end
    # If we cannot capture, we cannot send.
    alias sending_allowed? capture_allowed?

    def error_messages
      @errors = [errors[0]] + errors[1..-1].map(&:downcase) # fix case of all but first
      errors.join(", ")
    end

    def project_root=(root_dir)
      @project_root = root_dir
    end

    def rails_activesupport_breadcrumbs=(val)
      DeprecationHelper.deprecate_old_breadcrumbs_configuration(:active_support_logger)
      @rails_activesupport_breadcrumbs = val
    end

    def exception_class_allowed?(exc)
      if exc.is_a?(Sentry::Error)
        # Try to prevent error reporting loops
        logger.debug "Refusing to capture Sentry error: #{exc.inspect}"
        false
      elsif excluded_exception?(exc)
        logger.debug "User excluded error: #{exc.inspect}"
        false
      else
        true
      end
    end

    def enabled_in_current_env?
      environments.empty? || environments.include?(current_environment)
    end

    private

    def detect_project_root
      if defined? Rails.root # we are in a Rails application
        Rails.root.to_s
      else
        Dir.pwd
      end
    end

    def detect_release
      detect_release_from_env ||
        detect_release_from_git ||
        detect_release_from_capistrano ||
        detect_release_from_heroku
    rescue => e
      logger.error "Error detecting release: #{e.message}"
    end

    def excluded_exception?(incoming_exception)
      excluded_exceptions.any? do |excluded_exception|
        matches_exception?(get_exception_class(excluded_exception), incoming_exception)
      end
    end

    def get_exception_class(x)
      x.is_a?(Module) ? x : qualified_const_get(x)
    end

    def matches_exception?(excluded_exception_class, incoming_exception)
      if inspect_exception_causes_for_exclusion?
        Sentry::Utils::ExceptionCauseChain.exception_to_array(incoming_exception).any? { |cause| excluded_exception_class === cause }
      else
        excluded_exception_class === incoming_exception
      end
    end

    # In Ruby <2.0 const_get can't lookup "SomeModule::SomeClass" in one go
    def qualified_const_get(x)
      x = x.to_s
      if !x.match(/::/)
        Object.const_get(x)
      else
        x.split(MODULE_SEPARATOR).reject(&:empty?).inject(Object) { |a, e| a.const_get(e) }
      end
    rescue NameError # There's no way to safely ask if a constant exist for an unknown string
      nil
    end

    def detect_release_from_heroku
      return unless running_on_heroku?
      return if ENV['CI']
      logger.warn(HEROKU_DYNO_METADATA_MESSAGE) && return unless ENV['HEROKU_SLUG_COMMIT']

      ENV['HEROKU_SLUG_COMMIT']
    end

    def running_on_heroku?
      File.directory?("/etc/heroku")
    end

    def detect_release_from_capistrano
      revision_file = File.join(project_root, 'REVISION')
      revision_log = File.join(project_root, '..', 'revisions.log')

      if File.exist?(revision_file)
        File.read(revision_file).strip
      elsif File.exist?(revision_log)
        File.open(revision_log).to_a.last.strip.sub(/.*as release ([0-9]+).*/, '\1')
      end
    end

    def detect_release_from_git
      Sentry.sys_command("git rev-parse --short HEAD") if File.directory?(".git")
    end

    def detect_release_from_env
      ENV['SENTRY_RELEASE']
    end

    def capture_in_current_environment?
      return true if enabled_in_current_env?

      @errors << "Not configured to send/capture in environment '#{current_environment}'"
      false
    end

    def capture_allowed_by_callback?(message_or_exc)
      return true if !should_capture || message_or_exc.nil? || should_capture.call(message_or_exc)

      @errors << "should_capture returned false"
      false
    end

    def valid?
      return true if %w(server host path public_key project_id).all? { |k| public_send(k) }

      if server
        %w(server host path public_key project_id).map do |key|
          @errors << "No #{key} specified" unless public_send(key)
        end
      else
        @errors << "DSN not set"
      end
      false
    end

    def sample_allowed?
      return true if sample_rate == 1.0

      if Random::DEFAULT.rand >= sample_rate
        @errors << "Excluded by random sample"
        false
      else
        true
      end
    end

    # Try to resolve the hostname to an FQDN, but fall back to whatever
    # the load name is.
    def resolve_hostname
      Socket.gethostname ||
        Socket.gethostbyname(hostname).first rescue server_name
    end

    def current_environment_from_env
      ENV['SENTRY_CURRENT_ENV'] || ENV['SENTRY_ENVIRONMENT'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'default'
    end

    def server_name_from_env
      if running_on_heroku?
        ENV['DYNO']
      else
        resolve_hostname
      end
    end
  end
end
