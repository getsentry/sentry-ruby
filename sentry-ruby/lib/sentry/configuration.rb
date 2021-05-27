require "concurrent/utility/processor_counter"

require "sentry/utils/exception_cause_chain"
require "sentry/dsn"
require "sentry/transport/configuration"
require "sentry/linecache"
require "sentry/interfaces/stacktrace_builder"

module Sentry
  class Configuration
    include LoggingHelper
    # Directories to be recognized as part of your app. e.g. if you
    # have an `engines` dir at the root of your project, you may want
    # to set this to something like /(app|config|engines|lib)/
    attr_accessor :app_dirs_pattern

    # Provide an object that responds to `call` to send events asynchronously.
    # E.g.: lambda { |event| Thread.new { Sentry.send_event(event) } }
    attr_reader :async

    # to send events in a non-blocking way, sentry-ruby has its own background worker
    # by default, the worker holds a thread pool that has [the number of processors] threads
    # but you can configure it with this configuration option
    # E.g.: config.background_worker_threads = 5
    #
    # if you want to send events synchronously, set the value to 0
    # E.g.: config.background_worker_threads = 0
    attr_accessor :background_worker_threads

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

    # Optional Proc, called before adding the breadcrumb to the current scope
    # E.g.: lambda { |breadcrumb, hint| breadcrumb }
    # E.g.: lambda { |breadcrumb, hint| nil }
    # E.g.: lambda { |breadcrumb, hint|
    #   breadcrumb.message = 'a'
    #   breadcrumb
    # }
    attr_reader :before_breadcrumb

    # Optional Proc, called before sending an event to the server/
    # E.g.: lambda { |event, hint| event }
    # E.g.: lambda { |event, hint| nil }
    # E.g.: lambda { |event, hint|
    #   event[:message] = 'a'
    #   event
    # }
    attr_reader :before_send

    # An array of breadcrumbs loggers to be used. Available options are:
    # - :sentry_logger
    # - :active_support_logger
    attr_reader :breadcrumbs_logger

    # Max number of breadcrumbs a breadcrumb buffer can hold
    attr_accessor :max_breadcrumbs

    # Number of lines of code context to capture, or nil for none
    attr_accessor :context_lines

    # RACK_ENV by default.
    attr_reader :environment

    # Whether the SDK should run in the debugging mode. Default is false.
    # If set to true, SDK errors will be logged with backtrace
    attr_accessor :debug

    # the dsn value, whether it's set via `config.dsn=` or `ENV["SENTRY_DSN"]`
    attr_reader :dsn

    # Whitelist of enabled_environments that will send notifications to Sentry. Array of Strings.
    attr_accessor :enabled_environments

    # Logger 'progname's to exclude from breadcrumbs
    attr_accessor :exclude_loggers

    # Array of exception classes that should never be sent. See IGNORE_DEFAULT.
    # You should probably append to this rather than overwrite it.
    attr_accessor :excluded_exceptions

    # Boolean to check nested exceptions when deciding if to exclude. Defaults to false
    attr_accessor :inspect_exception_causes_for_exclusion
    alias inspect_exception_causes_for_exclusion? inspect_exception_causes_for_exclusion

    # You may provide your own LineCache for matching paths with source files.
    # This may be useful if you need to get source code from places other than
    # the disk. See Sentry::LineCache for the required interface you must implement.
    attr_accessor :linecache

    # Logger used by Sentry. In Rails, this is the Rails logger, otherwise
    # Sentry provides its own Sentry::Logger.
    attr_accessor :logger

    # Project directory root for in_app detection. Could be Rails root, etc.
    # Set automatically for Rails.
    attr_reader :project_root

    # Insert sentry-trace to outgoing requests' headers
    attr_accessor :propagate_traces

    # Array of rack env parameters to be included in the event sent to sentry.
    attr_accessor :rack_env_whitelist

    # Release tag to be passed with every event sent to Sentry.
    # We automatically try to set this to a git SHA or Capistrano release.
    attr_accessor :release

    # The sampling factor to apply to events. A value of 0.0 will not send
    # any events, and a value of 1.0 will send 100% of events.
    attr_accessor :sample_rate

    # Include module versions in reports - boolean.
    attr_accessor :send_modules

    # When send_default_pii's value is false (default), sensitive information like
    # - user ip
    # - user cookie
    # - request body
    # will not be sent to Sentry.
    attr_accessor :send_default_pii

    # Allow to skip Sentry emails within rake tasks
    attr_accessor :skip_rake_integration

    # IP ranges for trusted proxies that will be skipped when calculating IP address.
    attr_accessor :trusted_proxies

    attr_accessor :server_name

    # Return a Transport::Configuration object for transport-related configurations.
    attr_reader :transport

    # Take a float between 0.0 and 1.0 as the sample rate for tracing events (transactions).
    attr_accessor :traces_sample_rate

    # Take a Proc that controls the sample rate for every tracing event, e.g.
    # ```
    # lambda do |tracing_context|
    #   # tracing_context[:transaction_context] contains the information about the transaction
    #   # tracing_context[:parent_sampled] contains the transaction's parent's sample decision
    #   true # return value can be a boolean or a float between 0.0 and 1.0
    # end
    # ```
    attr_accessor :traces_sampler

    # these are not config options
    attr_reader :errors, :gem_specs

    # Most of these errors generate 4XX responses. In general, Sentry clients
    # only automatically report 5xx responses.
    IGNORE_DEFAULT = [
      'Mongoid::Errors::DocumentNotFound',
      'Rack::QueryParser::InvalidParameterError',
      'Rack::QueryParser::ParameterTypeError',
      'Sinatra::NotFound'
    ].freeze

    RACK_ENV_WHITELIST_DEFAULT = %w(
      REMOTE_ADDR
      SERVER_NAME
      SERVER_PORT
    ).freeze

    HEROKU_DYNO_METADATA_MESSAGE = "You are running on Heroku but haven't enabled Dyno Metadata. For Sentry's "\
    "release detection to work correctly, please run `heroku labs:enable runtime-dyno-metadata`".freeze

    LOG_PREFIX = "** [Sentry] ".freeze
    MODULE_SEPARATOR = "::".freeze

    # Post initialization callbacks are called at the end of initialization process
    # allowing extending the configuration of sentry-ruby by multiple extensions
    @@post_initialization_callbacks = []

    def initialize
      self.debug = false
      self.background_worker_threads = Concurrent.processor_count
      self.max_breadcrumbs = BreadcrumbBuffer::DEFAULT_SIZE
      self.breadcrumbs_logger = []
      self.context_lines = 3
      self.environment = environment_from_env
      self.enabled_environments = []
      self.exclude_loggers = []
      self.excluded_exceptions = IGNORE_DEFAULT.dup
      self.inspect_exception_causes_for_exclusion = true
      self.linecache = ::Sentry::LineCache.new
      self.logger = ::Sentry::Logger.new(STDOUT)
      self.project_root = Dir.pwd
      self.propagate_traces = true

      self.release = detect_release
      self.sample_rate = 1.0
      self.send_modules = true
      self.send_default_pii = false
      self.skip_rake_integration = false
      self.trusted_proxies = []
      self.dsn = ENV['SENTRY_DSN']
      self.server_name = server_name_from_env

      self.before_send = false
      self.rack_env_whitelist = RACK_ENV_WHITELIST_DEFAULT

      @transport = Transport::Configuration.new
      @gem_specs = Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)

      run_post_initialization_callbacks
    end

    def dsn=(value)
      return if value.nil? || value.empty?

      @dsn = DSN.new(value)
    end

    alias server= dsn=


    def async=(value)
      if value && !value.respond_to?(:call)
        raise(ArgumentError, "async must be callable")
      end

      @async = value
    end

    def breadcrumbs_logger=(logger)
      loggers =
        if logger.is_a?(Array)
          logger
        else
          Array(logger)
        end

      require "sentry/breadcrumb/sentry_logger" if loggers.include?(:sentry_logger)

      @breadcrumbs_logger = logger
    end

    def before_send=(value)
      unless value == false || value.respond_to?(:call)
        raise ArgumentError, "before_send must be callable (or false to disable)"
      end

      @before_send = value
    end

    def before_breadcrumb=(value)
      unless value.nil? || value.respond_to?(:call)
        raise ArgumentError, "before_breadcrumb must be callable (or nil to disable)"
      end

      @before_breadcrumb = value
    end

    def environment=(environment)
      @environment = environment.to_s
    end

    def sending_allowed?
      @errors = []

      valid? &&
        capture_in_environment? &&
        sample_allowed?
    end

    def error_messages
      @errors = [@errors[0]] + @errors[1..-1].map(&:downcase) # fix case of all but first
      @errors.join(", ")
    end

    def project_root=(root_dir)
      @project_root = root_dir
    end

    def exception_class_allowed?(exc)
      if exc.is_a?(Sentry::Error)
        # Try to prevent error reporting loops
        log_debug("Refusing to capture Sentry error: #{exc.inspect}")
        false
      elsif excluded_exception?(exc)
        log_debug("User excluded error: #{exc.inspect}")
        false
      else
        true
      end
    end

    def enabled_in_current_env?
      enabled_environments.empty? || enabled_environments.include?(environment)
    end

    def tracing_enabled?
      !!((@traces_sample_rate && @traces_sample_rate >= 0.0 && @traces_sample_rate <= 1.0) || @traces_sampler) && sending_allowed?
    end

    def stacktrace_builder
      @stacktrace_builder ||= StacktraceBuilder.new(
        project_root: @project_root.to_s,
        app_dirs_pattern: @app_dirs_pattern,
        linecache: @linecache,
        context_lines: @context_lines,
        backtrace_cleanup_callback: @backtrace_cleanup_callback
      )
    end

    private

    def detect_release
      detect_release_from_env ||
        detect_release_from_git ||
        detect_release_from_capistrano ||
        detect_release_from_heroku
    rescue => e
      log_error("Error detecting release", e, debug: debug)
    end

    def excluded_exception?(incoming_exception)
      excluded_exception_classes.any? do |excluded_exception|
        matches_exception?(excluded_exception, incoming_exception)
      end
    end

    def excluded_exception_classes
      @excluded_exception_classes ||= excluded_exceptions.map { |e| get_exception_class(e) }
    end

    def get_exception_class(x)
      x.is_a?(Module) ? x : safe_const_get(x)
    end

    def matches_exception?(excluded_exception_class, incoming_exception)
      if inspect_exception_causes_for_exclusion?
        Sentry::Utils::ExceptionCauseChain.exception_to_array(incoming_exception).any? { |cause| excluded_exception_class === cause }
      else
        excluded_exception_class === incoming_exception
      end
    end

    def safe_const_get(x)
      x = x.to_s unless x.is_a?(String)
      Object.const_get(x)
    rescue NameError # There's no way to safely ask if a constant exist for an unknown string
      nil
    end

    def detect_release_from_heroku
      return unless running_on_heroku?
      return if ENV['CI']
      log_warn(HEROKU_DYNO_METADATA_MESSAGE) && return unless ENV['HEROKU_SLUG_COMMIT']

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

    def capture_in_environment?
      return true if enabled_in_current_env?

      @errors << "Not configured to send/capture in environment '#{environment}'"
      false
    end

    def valid?
      if @dsn&.valid?
        true
      else
        @errors << "DSN not set or not valid"
        false
      end
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

    def environment_from_env
      ENV['SENTRY_CURRENT_ENV'] || ENV['SENTRY_ENVIRONMENT'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'default'
    end

    def server_name_from_env
      if running_on_heroku?
        ENV['DYNO']
      else
        resolve_hostname
      end
    end

    def run_post_initialization_callbacks
      self.class.post_initialization_callbacks.each do |hook|
        instance_eval(&hook)
      end
    end

    # allow extensions to add their hooks to the Configuration class
    def self.add_post_initialization_callback(&block)
      self.post_initialization_callbacks << block
    end

    protected

    def self.post_initialization_callbacks
      @@post_initialization_callbacks
    end
  end
end
