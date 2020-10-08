# frozen_string_literal: true

require 'socket'
require 'securerandom'
require 'sentry/event/options'
require 'sentry/interface'
require 'sentry/backtrace'
require 'sentry/utils/deep_merge'

module Sentry
  class Event
    # See Sentry server default limits at
    # https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
    MAX_MESSAGE_SIZE_IN_BYTES = 1024 * 8
    REQUIRED_OPTION_KEYS = [:configuration].freeze

    SDK = { "name" => "sentry.ruby", "version" => Sentry::VERSION }.freeze

    ATTRIBUTES = %i(
      event_id logger level time_spent timestamp
      checksum release environment server_name modules
      message user tags contexts extra
      fingerprint breadcrumbs backtrace transaction
      platform sdk
    )

    attr_accessor(*ATTRIBUTES)
    attr_reader :id, :configuration

    alias event_id id

    def initialize(options:, configuration:)
      # this needs to go first because some setters rely on configuration
      @configuration = configuration

      # Set some simple default values
      @id            = SecureRandom.uuid.delete("-")
      @timestamp     = Time.now.utc
      @platform      = :ruby
      @sdk           = SDK

      # Set some attributes with empty hashes to allow merging
      @interfaces        = {}

      @user          = options.user
      @extra         = options.extra
      @contexts      = options.contexts
      @tags          = configuration.tags.merge(options.tags)

      @checksum = options.checksum

      @fingerprint = options.fingerprint

      @server_name = options.server_name
      @environment = options.environment
      @release = options.release

      # these 2 needs custom setter methods
      self.level         = options.level
      self.message       = options.message if options.message

      # Allow attributes to be set on the event at initialization
      yield self if block_given?
      # options.each_pair { |key, val| public_send("#{key}=", val) unless val.nil? }

      if !options.backtrace.empty?
        interface(:stacktrace) do |int|
          int.frames = stacktrace_interface_from(options.backtrace)
        end
      end

      set_core_attributes_from_configuration
    end

    class << self
      def get_log_message(event_hash)
        message = event_hash[:message] || event_hash['message']
        message = get_message_from_exception(event_hash) if message.empty?
        message = '<no message value>' if message.empty?
        message
      end

      def get_message_from_exception(event_hash)
        (
          event_hash &&
          event_hash[:exception] &&
          event_hash[:exception][:values] &&
          event_hash[:exception][:values][0] &&
          "#{event_hash[:exception][:values][0][:type]}: #{event_hash[:exception][:values][0][:value]}"
        )
      end
    end

    def message
      @interfaces[:logentry]&.unformatted_message.to_s
    end

    def message=(message)
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
      data = ATTRIBUTES.each_with_object({}) do |att, memo|
        memo[att] = public_send(att) if public_send(att)
      end

      data[:breadcrumbs] = breadcrumbs.to_hash if breadcrumbs

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
      @server_name ||= configuration.server_name
      @release     ||= configuration.release
      @modules       = list_gem_specs if configuration.send_modules
      @environment ||= configuration.current_environment
    end

    def add_rack_context
      interface :http do |int|
        int.from_rack(context.rack_env)
      end
      # context.user[:ip_address] = calculate_real_ip_from_rack
    end

    # When behind a proxy (or if the user is using a proxy), we can't use
    # REMOTE_ADDR to determine the Event IP, and must use other headers instead.
    # def calculate_real_ip_from_rack
    #   Utils::RealIp.new(
    #     :remote_addr => context.rack_env["REMOTE_ADDR"],
    #     :client_ip => context.rack_env["HTTP_CLIENT_IP"],
    #     :real_ip => context.rack_env["HTTP_X_REAL_IP"],
    #     :forwarded_for => context.rack_env["HTTP_X_FORWARDED_FOR"]
    #   ).calculate_ip
    # end

    def list_gem_specs
      # Older versions of Rubygems don't support iterating over all specs
      Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)
    end
  end
end
