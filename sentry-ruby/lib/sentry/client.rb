require "sentry/transports"

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
