# frozen_string_literal: true

require 'socket'
require 'securerandom'
require 'sentry/interface'
require 'sentry/utils/deep_merge'

module Sentry
  class Event
    # See Sentry server default limits at
    # https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
    MAX_MESSAGE_SIZE_IN_BYTES = 1024 * 8
    REQUIRED_OPTION_KEYS = [:configuration].freeze

    SDK = { "name" => "sentry-ruby", "version" => Sentry::VERSION }.freeze

    attr_accessor :id, :logger, :transaction, :server_name, :release, :modules,
                  :extra, :tags, :context, :configuration, :checksum,
                  :fingerprint, :environment, :server_os, :runtime,
                  :breadcrumbs, :user, :backtrace, :platform, :sdk
    alias event_id id

    attr_reader :level, :timestamp, :time_spent

    def initialize(options)
      # Set some simple default values
      self.id            = SecureRandom.uuid.delete("-")
      self.timestamp     = Time.now.utc
      self.level         = :error
      self.logger        = :ruby
      self.platform      = :ruby
      self.sdk           = SDK

      # Set some attributes with empty hashes to allow merging
      @interfaces        = {}
      self.user          = {} # TODO: contexts
      self.extra         = {} # TODO: contexts
      self.server_os     = {} # TODO: contexts
      self.runtime       = {} # TODO: contexts
      self.tags          = {} # TODO: contexts

      unless REQUIRED_OPTION_KEYS.all? { |key| options.key?(key) }
        raise "you much provide configuration when initializing a Sentry::Event"
      end

      self.configuration = options[:configuration]

      # Allow attributes to be set on the event at initialization
      yield self if block_given?
      options.each_pair { |key, val| public_send("#{key}=", val) unless val.nil? }

      set_core_attributes_from_configuration
    end

    def self.from_exception(exc, options = {}, &block)
      exception_context = if exc.instance_variable_defined?(:@__sentry_context)
                            exc.instance_variable_get(:@__sentry_context)
                          elsif exc.respond_to?(:sentry_context)
                            exc.sentry_context
                          else
                            {}
                          end
      options = Sentry::Utils::DeepMergeHash.deep_merge(exception_context, options)

      return unless options[:configuration].exception_class_allowed?(exc)

      new(options) do |evt|
        evt.add_exception_interface(exc)
        yield evt if block
      end
    end

    def self.from_message(message, options = {})
      new(options) do |evt|
        evt.message = message, options[:message_params] || []
        if options[:backtrace]
          evt.interface(:stacktrace) do |int|
            int.frames = evt.stacktrace_interface_from(options[:backtrace])
          end
        end
      end
    end

    def message
      @interfaces[:logentry]&.unformatted_message
    end

    def message=(args)
      if args.is_a?(Array)
        message, params = args[0], args[0..-1]
      else
        message = args
      end

      unless message.is_a?(String)
        configuration.logger.debug("You're passing a non-string message")
        message = message.to_s
      end

      interface(:message) do |int|
        int.message = message.byteslice(0...MAX_MESSAGE_SIZE_IN_BYTES) # Messages limited to 10kb
        int.params = params
      end
    end

    def timestamp=(time)
      @timestamp = time.is_a?(Time) ? time.strftime('%Y-%m-%dT%H:%M:%S') : time
    end

    def time_spent=(time)
      @time_spent = time.is_a?(Float) ? (time * 1000).to_i : time
    end

    def level=(new_level) # needed to meet the Sentry spec
      @level = new_level.to_s == "warn" ? :warning : new_level
    end

    def interface(name, value = nil, &block)
      int = Interface.registered[name]
      raise(Error, "Unknown interface: #{name}") unless int

      @interfaces[int.sentry_alias] = int.new(value, &block) if value || block
      @interfaces[int.sentry_alias]
    end

    def [](key)
      interface(key)
    end

    def []=(key, value)
      interface(key, value)
    end

    def to_hash
      data = [:checksum, :environment, :event_id, :extra, :fingerprint, :level,
              :logger, :message, :modules, :platform, :release, :sdk, :server_name,
              :tags, :time_spent, :timestamp, :transaction, :user].each_with_object({}) do |att, memo|
        memo[att] = public_send(att) if public_send(att)
      end

      data[:breadcrumbs] = @breadcrumbs.to_hash unless @breadcrumbs.empty?

      @interfaces.each_pair do |name, int_data|
        data[name.to_sym] = int_data.to_hash
      end
      data
    end

    def to_json_compatible
      cleaned_hash = async_json_processors.reduce(to_hash) { |a, e| e.process(a) }
      JSON.parse(JSON.generate(cleaned_hash))
    end

    def add_exception_interface(exc)
      interface(:exception) do |exc_int|
        exceptions = Sentry::Utils::ExceptionCauseChain.exception_to_array(exc).reverse
        backtraces = Set.new
        exc_int.values = exceptions.map do |e|
          SingleExceptionInterface.new do |int|
            int.type = e.class.to_s
            int.value = e.to_s
            int.module = e.class.to_s.split('::')[0...-1].join('::')

            int.stacktrace =
              if e.backtrace && !backtraces.include?(e.backtrace.object_id)
                backtraces << e.backtrace.object_id
                StacktraceInterface.new do |stacktrace|
                  stacktrace.frames = stacktrace_interface_from(e.backtrace)
                end
              end
          end
        end
      end
    end

    def stacktrace_interface_from(backtrace)
      Backtrace.parse(backtrace, { configuration: configuration }).lines.reverse.each_with_object([]) do |line, memo|
        frame = StacktraceInterface::Frame.new
        frame.abs_path = line.file if line.file
        frame.function = line.method if line.method
        frame.lineno = line.number
        frame.in_app = line.in_app
        frame.module = line.module_name if line.module_name

        if configuration[:context_lines] && frame.abs_path
          frame.pre_context, frame.context_line, frame.post_context = \
            configuration.linecache.get_file_context(frame.abs_path, frame.lineno, configuration[:context_lines])
        end

        memo << frame if frame.filename
      end
    end

    # For cross-language compat
    class << self
      alias captureException from_exception
      alias captureMessage from_message
      alias capture_exception from_exception
      alias capture_message from_message
    end

    private

    def set_core_attributes_from_configuration
      self.server_name ||= configuration.server_name
      self.release     ||= configuration.release
      self.modules       = list_gem_specs if configuration.send_modules
      self.environment ||= configuration.current_environment
    end

    def set_core_attributes_from_context
      self.transaction ||= context.transaction.last

      # If this is a Rack event, merge Rack context
      add_rack_context if !self[:http] && context.rack_env

      # Merge contexts
      self.user = context.user.merge(user) # TODO: contexts
      self.extra = context.extra.merge(extra) # TODO: contexts
      self.tags = configuration.tags.merge(context.tags).merge!(tags) # TODO: contexts
    end

    def add_rack_context
      interface :http do |int|
        int.from_rack(context.rack_env)
      end
      context.user[:ip_address] = calculate_real_ip_from_rack
    end

    # When behind a proxy (or if the user is using a proxy), we can't use
    # REMOTE_ADDR to determine the Event IP, and must use other headers instead.
    def calculate_real_ip_from_rack
      Utils::RealIp.new(
        :remote_addr => context.rack_env["REMOTE_ADDR"],
        :client_ip => context.rack_env["HTTP_CLIENT_IP"],
        :real_ip => context.rack_env["HTTP_X_REAL_IP"],
        :forwarded_for => context.rack_env["HTTP_X_FORWARDED_FOR"]
      ).calculate_ip
    end

    def async_json_processors
      configuration.processors.map { |v| v.new(self) }
    end

    def list_gem_specs
      # Older versions of Rubygems don't support iterating over all specs
      Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)
    end
  end
end
