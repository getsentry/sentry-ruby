require 'faraday'

require 'raven/transports'
require 'raven/error'

module Raven

  module Transports

    class HTTP < Transport

      def send(auth_header, data, options = {})
        project_id = self.configuration[:project_id]
        response = conn.post "/api/#{project_id}/store/" do |req|
          req.headers['Content-Type'] = options[:content_type]
          req.headers['X-Sentry-Auth'] = auth_header
          req.body = data
        end
        Raven.logger.warn "Error from Sentry server (#{response.status}): #{response.body}" unless response.status == 200
      end

    private

      def conn
        @conn ||= begin
          self.verify_configuration

          Raven.logger.debug "Raven HTTP Transport connecting to #{self.configuration.server}"

          ssl_configuration = self.configuration.ssl || {}
          ssl_configuration[:verify] = self.configuration.ssl_verification

          conn = Faraday.new(
            :url => self.configuration[:server],
            :ssl => ssl_configuration
          ) do |builder|
            builder.adapter(*adapter)
          end

          if self.configuration.timeout
            conn.options[:timeout] = self.configuration.timeout
          end
          if self.configuration.open_timeout
            conn.options[:open_timeout] = self.configuration.open_timeout
          end

          conn
        end
      end

      def adapter
        configuration.http_adapter || Faraday.default_adapter
      end

    end

  end

end
