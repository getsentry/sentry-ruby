# frozen_string_literal: true

require 'socket'
require 'securerandom'
require 'sentry/interface'
require 'sentry/backtrace'
require 'sentry/utils/real_ip'
require 'sentry/utils/request_id'

module Sentry
  class Event
    ATTRIBUTES = %i(
      event_id level timestamp
      release environment server_name modules
      message user tags contexts extra
      fingerprint breadcrumbs backtrace transaction
      platform sdk type
    )

    MAX_MESSAGE_SIZE_IN_BYTES = 1024 * 8

    attr_accessor(*ATTRIBUTES)
    attr_reader :configuration, :request, :exception, :threads

    def initialize(configuration:, integration_meta: nil, message: nil)
      # this needs to go first because some setters rely on configuration
      @configuration = configuration

      # Set some simple default values
      @event_id      = SecureRandom.uuid.delete("-")
      @timestamp     = Sentry.utc_now.iso8601
      @platform      = :ruby
      @sdk           = integration_meta || Sentry.sdk_meta

      @user          = {}
      @extra         = {}
      @contexts      = {}
      @tags          = {}

      @fingerprint = []

      @server_name = configuration.server_name
      @environment = configuration.environment
      @release = configuration.release
      @modules = configuration.gem_specs if configuration.send_modules

      @message = (message || "").byteslice(0..MAX_MESSAGE_SIZE_IN_BYTES)

      self.level = :error
    end

    class << self
      def get_log_message(event_hash)
        message = event_hash[:message] || event_hash['message']

        return message unless message.nil? || message.empty?

        message = get_message_from_exception(event_hash)

        return message unless message.nil? || message.empty?

        message = event_hash[:transaction] || event_hash["transaction"]

        return message unless message.nil? || message.empty?

        '<no message value>'
      end

      def get_message_from_exception(event_hash)
        if exception = event_hash.dig(:exception, :values, 0)
          "#{exception[:type]}: #{exception[:value]}"
        elsif exception = event_hash.dig("exception", "values", 0)
          "#{exception["type"]}: #{exception["value"]}"
        end
      end
    end

    def timestamp=(time)
      @timestamp = time.is_a?(Time) ? time.to_f : time
    end

    def level=(new_level) # needed to meet the Sentry spec
      @level = new_level.to_s == "warn" ? :warning : new_level
    end

    def rack_env=(env)
      unless request || env.empty?
        env = env.dup

        add_request_interface(env)

        if configuration.send_default_pii
          user[:ip_address] = calculate_real_ip_from_rack(env)
        end

        if request_id = Utils::RequestId.read_from(env)
          tags[:request_id] = request_id
        end
      end
    end

    def type
    end

    def to_hash
      data = serialize_attributes
      data[:breadcrumbs] = breadcrumbs.to_hash if breadcrumbs
      data[:request] = request.to_hash if request
      data[:exception] = exception.to_hash if exception
      data[:threads] = threads.to_hash if threads

      data
    end

    def to_json_compatible
      JSON.parse(JSON.generate(to_hash))
    end

    def add_request_interface(env)
      @request = Sentry::RequestInterface.build(env: env)
    end

    def add_threads_interface(backtrace: nil, **options)
      @threads = ThreadsInterface.build(
        backtrace: backtrace,
        stacktrace_builder: configuration.stacktrace_builder,
        **options
      )
    end

    def add_exception_interface(exception)
      if exception.respond_to?(:sentry_context)
        @extra.merge!(exception.sentry_context)
      end

      @exception = Sentry::ExceptionInterface.build(exception: exception, stacktrace_builder: configuration.stacktrace_builder)
    end

    private

    def serialize_attributes
      self.class::ATTRIBUTES.each_with_object({}) do |att, memo|
        if value = public_send(att)
          memo[att] = value
        end
      end
    end

    # When behind a proxy (or if the user is using a proxy), we can't use
    # REMOTE_ADDR to determine the Event IP, and must use other headers instead.
    def calculate_real_ip_from_rack(env)
      Utils::RealIp.new(
        :remote_addr => env["REMOTE_ADDR"],
        :client_ip => env["HTTP_CLIENT_IP"],
        :real_ip => env["HTTP_X_REAL_IP"],
        :forwarded_for => env["HTTP_X_FORWARDED_FOR"],
        :trusted_proxies => configuration.trusted_proxies
      ).calculate_ip
    end
  end
end
