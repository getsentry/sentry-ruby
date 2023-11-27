# frozen_string_literal: true

require "net/http"
require "zlib"

module Sentry
    
  # Spotlight Transport class is like HTTPTransport,
  # but it's experimental, with limited featureset. 
  # - It does not care about rate limits, assuming working with local Sidecar proxy
  # - Designed to just report events to Spotlight in development.
  #  
  # TODO: This needs a cleanup, we could extract most of common code into a module.
  class Spotlight
    GZIP_ENCODING = "gzip"
    GZIP_THRESHOLD = 1024 * 30
    CONTENT_TYPE = 'application/x-sentry-envelope'
    USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"
    
    # Takes the sidecar URL in and initializes the new Spotlight transport.
    # HTTPTransport will call this if config.spotlight is truthy, and pass it here.
    # so sidecar_url arg can either be true, or a string with the sidecar URL.
    def initialize(sidecar_url)
      @sidecar_url = sidecar_url.is_a?(String) ? sidecar_url : "http://localhost:8769/stream"
    end

    def send_data(data)
      headers = {
        'Content-Type' => CONTENT_TYPE,
        'Content-Encoding' => "",
        'User-Agent' => USER_AGENT
      }

      response = conn.start do |http|
        request = ::Net::HTTP::Post.new(@sidecar_url, headers)
        request.body = data
        http.request(request)
      end

      unless response.code.match?(/\A2\d{2}/)
        error_info = "the server responded with status #{response.code}"
        error_info += "\nbody: #{response.body}"
        error_info += " Error in headers is: #{response['x-sentry-error']}" if response['x-sentry-error']

        raise Sentry::ExternalError, error_info
      end

    # TODO: We might want to rescue the other HTTP_ERRORS like in HTTPTransport
    rescue SocketError, * Sentry::HTTPTransport::HTTP_ERRORS => e
      raise Sentry::ExternalError.new(e.message)
    end

    private

    # Similar to HTTPTransport connection, but does not support Proxy and SSL 
    def conn
      sidecar = URI(@sidecar_url)
      connection = ::Net::HTTP.new(sidecar.hostname, sidecar.port, nil)
      connection.use_ssl = false
      connection
    end
  end
end
