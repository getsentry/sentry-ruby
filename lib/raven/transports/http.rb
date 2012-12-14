require 'faraday'

require 'raven/transport'
require 'raven/error'

module Raven

  module Transport

    class HTTP < Transport

      AUTH_HEADER_KEY = 'X-Sentry-Auth'

      def send(auth_header, data, options = {})
        response = conn.post '/api/store/' do |req|
          req.headers['Content-Type'] = options[:content_type]
          req.headers[AUTH_HEADER_KEY] = auth_header
          req.body = data
        end
        raise Error.new("Error from Sentry server (#{response.status}): #{response.body}") unless response.status == 200
      end

    private

      def conn
        @conn ||= begin
          self.verify_configuration

          Raven.logger.debug "Raven HTTP Transport connecting to #{self.configuration.server}"
          Faraday.new(:url => self.configuration[:server]) do |builder|
            builder.adapter Faraday.default_adapter
            builder.options[:timeout] = self.configuration.timeout if self.configuration.timeout
            builder.options[:open_timeout] = self.configuration.open_timeout if self.configuration.open_timeout
          end
        end
      end

    end

  end

end
