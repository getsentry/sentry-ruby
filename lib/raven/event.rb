# frozen_string_literal: true
require 'securerandom'

module Raven
  class Event
    # See Sentry server default limits at
    # https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
    MAX_MESSAGE_SIZE_IN_BYTES = 1024 * 8
    TIME_FORMAT = '%Y-%m-%dT%H:%M:%S'.freeze
    SDK = { "name" => "raven-ruby", "version" => Raven::VERSION }.freeze

    attr_accessor :event_id, :logger, :transaction, :server_name, :release, :modules,
                  :extra, :tags, :checksum, :fingerprint, :environment, :user,
                  :backtrace, :platform, :sdk, :instance
    attr_reader   :level, :timestamp, :time_spent

    extend Forwardable
    def_delegators :instance, :configuration, :breadcrumbs, :context

    def initialize(init = {})
      self.instance      = Raven.instance
      self.event_id      = SecureRandom.uuid.delete!("-")
      self.timestamp     = Time.now.utc
      self.level         = :error
      self.logger        = :ruby
      self.platform      = :ruby
      self.sdk           = SDK

      # Set some attributes with empty hashes to allow merging
      @interfaces        = {}
      self.user          = {} # TODO: contexts
      self.extra         = {} # TODO: contexts
      self.tags          = {} # TODO: contexts

      init.each_pair { |key, val| public_send("#{key}=", val) }
      yield self if block_given?

      set_core_attributes_from_configuration
      set_core_attributes_from_context
    end

    def self.from_exception(exc, options = {}, &block)
      options = Raven::Utils::DeepMergeHash.deep_merge(exception_context(exc), options)

      new(options) do |evt|
        evt.message = "#{exc.class}: #{exc.message}"

        yield evt if block

        evt.interface(:exception) do |exc_int|
          exc_int.values = ExceptionInterface.from_exception(exc, evt.configuration)
        end
      end
    end

    def self.exception_context(exc)
      if exc.instance_variable_defined?(:@__raven_context)
        exc.instance_variable_get(:@__raven_context)
      elsif exc.respond_to?(:raven_context)
        exc.raven_context
      else
        {}
      end
    end

    def self.from_message(message, options = {})
      new(options) do |evt|
        evt.message = message, options[:message_params] || []
        if options[:backtrace]
          evt.interface(:stacktrace) do |int|
            int.frames = StacktraceInterface::Frame.from_backtrace(options[:backtrace], evt.configuration)
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

    def timestamp=(time)
      @timestamp = time.is_a?(Time) ? time.utc.strftime(TIME_FORMAT) : time
    end

    def time_spent=(time)
      @time_spent = time.is_a?(Float) ? (time * 1000).to_i : time
    end

    def level=(new_level) # needed to meet the Sentry spec
      @level = (new_level.to_sym == :warn) ? :warning : new_level
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
        val = public_send(att)
        memo[att] = val unless val.nil?
      end

      data[:breadcrumbs] = breadcrumbs.to_hash unless breadcrumbs.empty?

      @interfaces.each_pair do |name, int_data|
        data[name.to_sym] = int_data.to_hash
      end
      data
    end

    def to_json_compatible
      cleaned_hash = async_json_processors.reduce(to_hash) { |a, e| e.process(a) }
      JSON.parse(JSON.generate(cleaned_hash))
    end

    private

    def set_core_attributes_from_configuration
      self.server_name ||= configuration.server_name
      self.release     ||= configuration.release
      self.modules     ||= configuration.modules
      self.environment ||= configuration.current_environment
    end

    # TODO: dup context and modify/delegate
    def set_core_attributes_from_context
      self.transaction ||= context.transaction.last

      # If this is a Rack event, merge Rack context
      add_rack_context if !self[:http] && !context.rack_env.empty?

      # Merge contexts
      self.user  = context.user.merge(user) # TODO: contexts
      self.extra = context.extra.merge(extra) # TODO: contexts
      self.tags  = configuration.tags.merge(context.tags).merge!(tags) # TODO: contexts
    end

    def add_rack_context
      interface(:http) { |int| int.from_rack(context.rack_env) }

      # When behind a proxy (or if the user is using a proxy), we can't use
      # REMOTE_ADDR to determine the Event IP, and must use other headers instead.
      context.user[:ip_address] = Utils::RealIp.new(context.rack_env).calculate_ip
    end

    def async_json_processors
      [Raven::Processor::RemoveCircularReferences, Raven::Processor::UTF8Conversion].map { |v| v.new(nil) }
    end
  end
end
