# frozen_string_literal: true

require "net/http"
require "zlib"

module Sentry
  module Spotlight


    # Spotlight Transport class is like HTTPTransport,
    # but it's experimental, with limited featureset. 
    # - It does not care about rate limits, assuming working with local Sidecar proxy
    # - Designed to just report events to Spotlight in development.
    #  
    # TODO: This needs a cleanup, we could extract most of common code into a module.
    class Transport

      GZIP_ENCODING = "gzip"
      GZIP_THRESHOLD = 1024 * 30
      CONTENT_TYPE = 'application/x-sentry-envelope'
      USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"
      
      # Initialize a new Spotlight transport
      # with the provided Spotlight configuration.
      def initialize(spotlight_configuration)
        @configuration = spotlight_configuration
      end

      def send_data(data)
        encoding = ""

        if should_compress?(data)
          data = Zlib.gzip(data)
          encoding = GZIP_ENCODING
        end
  
        headers = {
          'Content-Type' => CONTENT_TYPE,
          'Content-Encoding' => encoding,
          'X-Sentry-Auth' => generate_auth_header,
          'User-Agent' => USER_AGENT
        }
  
        response = conn.start do |http|
          request = ::Net::HTTP::Post.new(@configuration.sidecar_url, headers)
          request.body = data
          http.request(request)
        end
  
        unless response.code.match?(/\A2\d{2}/)
          error_info = "the server responded with status #{response.code}"
          error_info += "\nbody: #{response.body}"
          error_info += " Error in headers is: #{response['x-sentry-error']}" if response['x-sentry-error']
  
          raise Sentry::ExternalError, error_info
        end
      rescue SocketError => e
        raise Sentry::ExternalError.new(e.message)
      end

      private

      def should_compress?(data)
        @transport_configuration.encoding == GZIP_ENCODING && data.bytesize >= GZIP_THRESHOLD
      end

      # Similar to HTTPTransport connection, but does not support Proxy and SSL 
      def conn
        sidecar = URL(@configuration.sidecar_url)
        connection = ::Net::HTTP.new(sidecar.hostname, sidecar.port, nil)
        connection.use_ssl = false
        connection
      end
      
    end
  end
end
