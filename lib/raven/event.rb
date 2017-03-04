# frozen_string_literal: true
require 'rubygems'
require 'socket'
require 'securerandom'
require 'digest/md5'

require 'raven/error'
require 'raven/linecache'

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

    BACKTRACE_RE = /^(.+?):(\d+)(?::in `(.+?)')?$/

    PLATFORM = "ruby".freeze
    SDK = { "name" => "raven-ruby", "version" => Raven::VERSION }.freeze

    attr_accessor :id, :timestamp, :time_spent, :level, :logger,
                  :culprit, :server_name, :release, :modules, :extra, :tags,
                  :context, :configuration, :checksum, :fingerprint, :environment,
                  :server_os, :runtime, :breadcrumbs, :user, :backtrace, :linecache

    def initialize(init = {})
      @configuration = init[:configuration] || Raven.configuration
      @interfaces    = {}
      @breadcrumbs   = init[:breadcrumbs] || Raven.breadcrumbs
      @context       = init[:context] || Raven.context
      @linecache     = @configuration.linecache
      @id            = SecureRandom.uuid.delete("-")
      @timestamp     = Time.now.utc
      @time_spent    = nil
      @level         = :error
      @logger        = ''
      @culprit       = nil
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

    def message
      @interfaces[:logentry] && @interfaces[:logentry].unformatted_message
    end

    def message=(args)
      message, params = *args
      interface(:message) do |int|
        int.message = message
        int.params = params
      end
    end

    class << self
      def from_exception(exc, options = {}, &block)
        exception_context = get_exception_context(exc) || {}
        options = Raven::Utils::DeepMergeHash.deep_merge(exception_context, options)

        configuration = options[:configuration] || Raven.configuration
        if exc.is_a?(Raven::Error)
          # Try to prevent error reporting loops
          configuration.logger.debug "Refusing to capture Raven error: #{exc.inspect}"
          return nil
        end
        if configuration[:excluded_exceptions].any? { |x| get_exception_class(x) === exc }
          configuration.logger.debug "User excluded error: #{exc.inspect}"
          return nil
        end

        new(options) do |evt|
          evt.configuration = configuration
          evt.message = "#{exc.class}: #{exc.message}".byteslice(0...10_000) # Messages limited to 10kb
          evt.level = options[:level] || :error

          add_exception_interface(evt, exc)

          yield evt if block
        end
      end

      def from_message(message, options = {})
        message = message.byteslice(0...10_000) # Messages limited to 10kb
        configuration = options[:configuration] || Raven.configuration

        new(options) do |evt|
          evt.configuration = configuration
          evt.level = options[:level] || :error
          evt.message = message, options[:message_params] || []
          if options[:backtrace]
            evt.interface(:stacktrace) do |int|
              stacktrace_interface_from(int, evt, options[:backtrace])
            end
          end
        end
      end

      private

      def get_exception_class(x)
        x.is_a?(Module) ? x : qualified_const_get(x)
      end

      # In Ruby <2.0 const_get can't lookup "SomeModule::SomeClass" in one go
      def qualified_const_get(x)
        x = x.to_s
        parts = x.split("::")
        parts.reject!(&:empty?)

        if parts.size < 2
          Object.const_get(x)
        else
          parts.inject(Object) { |a, e| a.const_get(e) }
        end
      rescue NameError # There's no way to safely ask if a constant exist for an unknown string
        nil
      end

      def get_exception_context(exc)
        if exc.instance_variable_defined?(:@__raven_context)
          exc.instance_variable_get(:@__raven_context)
        elsif exc.respond_to?(:raven_context)
          exc.raven_context
        end
      end

      def add_exception_interface(evt, exc)
        evt.interface(:exception) do |exc_int|
          exceptions = [exc]
          context = Set.new [exc.object_id]
          backtraces = Set.new

          while exc.respond_to?(:cause) && exc.cause
            exc = exc.cause
            break if context.include?(exc.object_id)
            exceptions << exc
            context.add(exc.object_id)
          end
          exceptions.reverse!

          exc_int.values = exceptions.map do |e|
            SingleExceptionInterface.new do |int|
              int.type = e.class.to_s
              int.value = e.to_s
              int.module = e.class.to_s.split('::')[0...-1].join('::')

              int.stacktrace =
                if e.backtrace && !backtraces.include?(e.backtrace.object_id)
                  backtraces << e.backtrace.object_id
                  StacktraceInterface.new do |stacktrace|
                    stacktrace_interface_from(stacktrace, evt, e.backtrace)
                  end
                end
            end
          end
        end
      end

      def stacktrace_interface_from(int, evt, backtrace)
        backtrace = Backtrace.parse(backtrace)

        int.frames = []
        backtrace.lines.reverse_each do |line|
          frame = StacktraceInterface::Frame.new
          frame.abs_path = line.file if line.file
          frame.function = line.method if line.method
          frame.lineno = line.number
          frame.in_app = line.in_app
          frame.module = line.module_name if line.module_name

          if evt.configuration[:context_lines] && frame.abs_path
            frame.pre_context, frame.context_line, frame.post_context = \
              evt.get_file_context(frame.abs_path, frame.lineno, evt.configuration[:context_lines])
          end

          int.frames << frame if frame.filename
        end

        evt.culprit = evt.get_culprit(int.frames)
      end
    end

    def list_gem_specs
      # Older versions of Rubygems don't support iterating over all specs
      Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)
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
      data[:culprit] = @culprit if @culprit
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

    def get_file_context(filename, lineno, context)
      linecache.get_file_context(filename, lineno, context)
    end

    def get_culprit(frames)
      lastframe = frames.reverse.find(&:in_app) || frames.last
      "#{lastframe.filename} in #{lastframe.function} at line #{lastframe.lineno}" if lastframe
    end

    def to_json_compatible
      JSON.parse(JSON.generate(to_hash))
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
  end
end
