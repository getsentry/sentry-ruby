# frozen_string_literal: true

require "net/http"
require "zlib"

module Sentry
  # Designed to just report events to Spotlight in development.
  class SpotlightTransport < HTTPTransport
    DEFAULT_SIDECAR_URL = "http://localhost:8969/stream"

    def initialize(configuration)
      super
      @sidecar_url = configuration.spotlight.is_a?(String) ? configuration.spotlight : DEFAULT_SIDECAR_URL
    end

    def endpoint
      "/stream"
    end

    # Similar to HTTPTransport connection, but does not support Proxy and SSL
    def conn
      sidecar = URI(@sidecar_url)
      connection = ::Net::HTTP.new(sidecar.hostname, sidecar.port, nil)
      connection.use_ssl = false
      connection
    end
  end
end
