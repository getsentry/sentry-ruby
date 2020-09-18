require "sentry/transports"
require 'sentry/utils/deep_merge'

module Sentry
  class Client
    PROTOCOL_VERSION = '5'
    USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"
    CONTENT_TYPE = 'application/json'

    attr_reader :transport, :configuration

    def initialize(configuration)
      @configuration = configuration
      @transport = case configuration.scheme
        when 'http', 'https'
          Transports::HTTP.new(configuration)
        when 'stdout'
          Transports::Stdout.new(configuration)
        when 'dummy'
          Transports::Dummy.new(configuration)
        else
          fail "Unknown transport scheme '#{configuration.scheme}'"
        end
    end

    def event_from_exception(exception, message: nil, extra: {})
      options = {
        message: message,
        extra: extra,
        configuration: configuration
      }

      exception_context =
        if exception.instance_variable_defined?(:@__sentry_context)
          exception.instance_variable_get(:@__sentry_context)
        elsif exception.respond_to?(:sentry_context)
          exception.sentry_context
        else
          {}
        end

      options = Utils::DeepMergeHash.deep_merge(exception_context, options)

      return unless @configuration.exception_class_allowed?(exception)

      Event.new(**options) do |evt|
        evt.add_exception_interface(exception)
        yield evt if block_given?
      end
    end

    def generate_auth_header
      now = Time.now.to_i.to_s
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => configuration.public_key
      }
      fields['sentry_secret'] = configuration.secret_key unless configuration.secret_key.nil?
      'Sentry ' + fields.map { |key, value| "#{key}=#{value}" }.join(', ')
    end
  end
end
