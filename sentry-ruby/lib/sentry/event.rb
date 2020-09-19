# frozen_string_literal: true

require 'socket'
require 'securerandom'
require 'sentry/interface'
require 'sentry/backtrace'
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

    def initialize(
      configuration:,
      message: nil,
      user: {}, extra: {}, tags: {},
      backtrace: [], level: :error, checksum: nil, fingerprint: [],
      server_name: nil, release: nil, environment: nil
    )
      # this needs to go first because some setters rely on configuration
      self.configuration = configuration

      # Set some simple default values
      self.id            = SecureRandom.uuid.delete("-")
      self.timestamp     = Time.now.utc
      self.level         = level
      self.platform      = :ruby
      self.sdk           = SDK

      # Set some attributes with empty hashes to allow merging
      @interfaces        = {}

      self.user          = user || {}
      self.extra         = extra || {}
      self.tags          = configuration.tags.merge(tags || {})

      self.message       = message
      self.server_os     = {} # TODO: contexts
      self.runtime       = {} # TODO: contexts

      self.checksum = checksum
      self.fingerprint = fingerprint

      self.server_name = server_name
      self.environment = environment
      self.release = release

      # Allow attributes to be set on the event at initialization
      yield self if block_given?
      # options.each_pair { |key, val| public_send("#{key}=", val) unless val.nil? }

      if !backtrace.empty?
        interface(:stacktrace) do |int|
          int.frames = stacktrace_interface_from(backtrace)
        end
      end

      set_core_attributes_from_configuration
    end

    def message
      @interfaces[:logentry]&.unformatted_message
    end

    def message=(message)
      unless message.is_a?(String)
        configuration.logger.debug("You're passing a non-string message")
        message = message.to_s
      end

      interface(:message) do |int|
        int.message = message.byteslice(0...MAX_MESSAGE_SIZE_IN_BYTES) # Messages limited to 10kb
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

      # TODO-v4: Fix this
      # data[:breadcrumbs] = @breadcrumbs.to_hash unless @breadcrumbs.empty?

      @interfaces.each_pair do |name, int_data|
        data[name.to_sym] = int_data.to_hash
      end
      data
    end

    def to_json_compatible
      JSON.parse(JSON.generate(to_hash))
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
      Backtrace.parse(backtrace, configuration: configuration).lines.reverse.each_with_object([]) do |line, memo|
        frame = StacktraceInterface::Frame.new(configuration: configuration)
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

    private

    def set_core_attributes_from_configuration
      self.server_name ||= configuration.server_name
      self.release     ||= configuration.release
      self.modules       = list_gem_specs if configuration.send_modules
      self.environment ||= configuration.current_environment
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

    def list_gem_specs
      # Older versions of Rubygems don't support iterating over all specs
      Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)
    end
  end
end
