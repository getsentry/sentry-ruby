# frozen_string_literal: true

module Sentry
  class Transport
    class Configuration
      attr_accessor :timeout, :open_timeout, :proxy, :ssl, :ssl_ca_file, :ssl_verification, :encoding
      attr_reader :transport_class

      def initialize
        @ssl_verification = true
        @open_timeout = 1
        @timeout = 2
        @encoding = HTTPTransport::GZIP_ENCODING
      end

      def transport_class=(klass)
        unless klass.is_a?(Class)
          raise Sentry::Error.new("config.transport.transport_class must a class. got: #{klass.class}")
        end

        @transport_class = klass
      end
    end
  end
end
