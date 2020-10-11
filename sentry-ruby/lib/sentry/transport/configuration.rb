module Sentry
  class Transport
    class Configuration
      attr_accessor :timeout, :open_timeout, :proxy, :ssl, :ssl_ca_file, :ssl_verification, :encoding, :http_adapter, :faraday_builder

      def initialize
        @ssl_verification = true
        @open_timeout = 1
        @timeout = 2
        @encoding = 'gzip'
      end

      def encoding=(encoding)
        raise(Error, 'Unsupported encoding') unless %w(gzip json).include? encoding

        @encoding = encoding
      end
    end
  end
end
