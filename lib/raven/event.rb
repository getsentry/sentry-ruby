# frozen_string_literal: true
require 'rubygems'
require 'socket'
require 'securerandom'
require 'digest/md5'

require 'raven/error'

module Raven
  class Event
    LOG_LEVELS = {
      "debug" => 10,
      "info" => 20,
      "warn" => 30,
      "warning" => 30,
      "error" => 40,
      "fatal" => 50
    }.freeze

    # See Sentry server default limits at
    # https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
    MAX_MESSAGE_SIZE_IN_BYTES = 1024 * 8

    PLATFORM = "ruby".freeze
    SDK = { "name" => "raven-ruby", "version" => Raven::VERSION }.freeze

    attr_accessor :id, :timestamp, :time_spent, :level, :logger,
                  :transaction, :server_name, :release, :modules, :extra, :tags,
                  :context, :configuration, :checksum, :fingerprint, :environment,
                  :server_os, :runtime, :breadcrumbs, :user, :backtrace

    def initialize(init = {})
      @configuration = init[:configuration] || Raven.configuration
      @interfaces    = {}
      @breadcrumbs   = init[:breadcrumbs] || Raven.breadcrumbs
      @context       = init[:context] || Raven.context
      @id            = SecureRandom.uuid.delete("-")
      @timestamp     = Time.now.utc
      @time_spent    = nil
      @level         = :error
      @logger        = PLATFORM
      @transaction   = @context.transaction.last
      @server_name   = @configuration.server_name
      @release       = @configuration.release
      @modules       = list_gem_specs if @configuration.send_modules
      @user          = {} # TODO: contexts
      @extra         = {} # TODO: contexts
      @server_os     = {} # TODO: contexts
      @runtime       = {} # TODO: contexts
      @tags          = {} # TODO: contexts
      @checksum      = nil
      @fingerprint   = nil
      @environment   = @configuration.current_environment

      yield self if block_given?

      if !self[:http] && @context.rack_env
        interface :http do |int|
          int.from_rack(@context.rack_env)
        end
      end

      if @context.rack_env # TODO: contexts
        @context.user[:ip_address] = calculate_real_ip_from_rack
      end

      init.each_pair { |key, val| public_send(key.to_s + "=", val) }

      @user = @context.user.merge(@user) # TODO: contexts
      @extra = @context.extra.merge(@extra) # TODO: contexts
      @tags = @configuration.tags.merge(@context.tags).merge(@tags) # TODO: contexts

      # Some type coercion
      @timestamp  = @timestamp.strftime('%Y-%m-%dT%H:%M:%S') if @timestamp.is_a?(Time)
      @time_spent = (@time_spent * 1000).to_i if @time_spent.is_a?(Float)
      @level      = LOG_LEVELS[@level.to_s.downcase] if @level.is_a?(String) || @level.is_a?(Symbol)
    end

    def self.from_exception(exc, options = {}, &block)
      exception_context = if exc.instance_variable_defined?(:@__raven_context)
                            exc.instance_variable_get(:@__raven_context)
                          elsif exc.respond_to?(:raven_context)
                            exc.raven_context
                          else
                            {}
                          end
      options = Raven::Utils::DeepMergeHash.deep_merge(exception_context, options)

      configuration = options[:configuration] || Raven.configuration
      return unless configuration.exception_class_allowed?(exc)

      new(options) do |evt|
        evt.configuration = configuration
        evt.message = "#{exc.class}: #{exc.message}"
        evt.level = options[:level] || :error

        evt.add_exception_interface(exc)

        yield evt if block
      end
    end

    def self.from_message(message, options = {})
      new(options) do |evt|
        evt.configuration = options[:configuration] || Raven.configuration
        evt.level = options[:level] || :error
        evt.message = message, options[:message_params] || []
        if options[:backtrace]
          evt.interface(:stacktrace) do |int|
            int.frames = evt.stacktrace_interface_from(options[:backtrace])
          end
        end
      end
    end

    def message
      @interfaces[:logentry] && @interfaces[:logentry].unformatted_message
    end

    def message=(args)
      message, params = *args
      interface(:message) do |int|
        int.message = message.byteslice(0...MAX_MESSAGE_SIZE_IN_BYTES) # Messages limited to 10kb
        int.params = params
      end
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
      data = {
        :event_id => @id,
        :timestamp => @timestamp,
        :time_spent => @time_spent,
        :level => @level,
        :platform => PLATFORM,
        :sdk => SDK
      }

      data[:logger] = @logger if @logger
      data[:transaction] = @transaction if @transaction
      data[:server_name] = @server_name if @server_name
      data[:release] = @release if @release
      data[:environment] = @environment if @environment
      data[:fingerprint] = @fingerprint if @fingerprint
      data[:modules] = @modules if @modules
      data[:extra] = @extra if @extra
      data[:tags] = @tags if @tags
      data[:user] = @user if @user
      data[:breadcrumbs] = @breadcrumbs.to_hash unless @breadcrumbs.empty?
      data[:checksum] = @checksum if @checksum

      @interfaces.each_pair do |name, int_data|
        data[name.to_sym] = int_data.to_hash
      end
      data[:message] = message
      data
    end

    def to_json_compatible
      cleaned_hash = async_json_processors.reduce(to_hash) { |a, e| e.process(a) }
      JSON.parse(JSON.generate(cleaned_hash))
    end

    def add_exception_interface(exc)
      interface(:exception) do |exc_int|
        exceptions = exception_chain_to_array(exc)
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
      Backtrace.parse(backtrace).lines.reverse.each_with_object([]) do |line, memo|
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
      [
        Raven::Processor::RemoveCircularReferences,
        Raven::Processor::UTF8Conversion
      ].map { |v| v.new(self) }
    end

    def exception_chain_to_array(exc)
      if exc.respond_to?(:cause) && exc.cause
        exceptions = [exc]
        while exc.cause
          exc = exc.cause
          break if exceptions.any? { |e| e.object_id == exc.object_id }
          exceptions << exc
        end
        exceptions.reverse!
      else
        [exc]
      end
    end

    def list_gem_specs
      # Older versions of Rubygems don't support iterating over all specs
      Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)
    end
  end
end
