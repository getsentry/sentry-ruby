require 'faraday'

require 'raven/transports'
require 'raven/error'

module Raven
  module Transports
    class HTTP < Transport
      attr_accessor :conn, :adapter

      def initialize(*args)
        super
        self.adapter = configuration.http_adapter || Faraday.default_adapter
        self.conn = set_conn
      end

      def send_event(auth_header, data, options = {})
        project_id = configuration[:project_id]
        path = configuration[:path] + "/"

        conn.post "#{path}api/#{project_id}/store/" do |req|
          req.headers['Content-Type'] = options[:content_type]
          req.headers['X-Sentry-Auth'] = auth_header
          req.body = data
        end
      rescue Faraday::ClientError => ex
        raise Raven::Error, ex.message
      end

      private

      def set_conn
        verify_configuration

        Raven.logger.debug "Raven HTTP Transport connecting to #{configuration.server}"

        ssl_configuration = configuration.ssl || {}
        ssl_configuration[:verify] = configuration.ssl_verification
        ssl_configuration[:ca_file] = configuration.ssl_ca_file

        conn = Faraday.new(
          :url => configuration[:server],
          :ssl => ssl_configuration
        ) do |builder|
          builder.response :raise_error
          builder.adapter(*adapter)
        end

        conn.headers[:user_agent] = "sentry-ruby/#{Raven::VERSION}"

        conn.options[:proxy] = configuration.proxy if configuration.proxy
        conn.options[:timeout] = configuration.timeout if configuration.timeout
        conn.options[:open_timeout] = configuration.open_timeout if configuration.open_timeout

        conn
      end
    end
  end
end
