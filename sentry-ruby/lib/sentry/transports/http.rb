require 'faraday'

module Sentry
  module Transports
    class HTTP < Transport
      attr_accessor :conn, :adapter

      def initialize(*args)
        super
        self.adapter = configuration.http_adapter || Faraday.default_adapter
        self.conn = set_conn
      end

      def send_event(auth_header, data, options = {})
        unless configuration.sending_allowed?
          logger.debug("Event not sent: #{configuration.error_messages}")
        end

        project_id = configuration[:project_id]
        path = configuration[:path] + "/"

        conn.post "#{path}api/#{project_id}/store/" do |req|
          req.headers['Content-Type'] = options[:content_type]
          req.headers['X-Sentry-Auth'] = auth_header
          req.body = data
        end
      rescue Faraday::Error => e
        error_info = e.message
        if e.response && e.response[:headers]['x-sentry-error']
          error_info += " Error in headers is: #{e.response[:headers]['x-sentry-error']}"
        end
        raise Sentry::Error, error_info
      end

      private

      def set_conn
        configuration.logger.debug "Sentry HTTP Transport connecting to #{configuration.server}"

        proxy = configuration.public_send(:proxy)

        Faraday.new(configuration.server, :ssl => ssl_configuration, :proxy => proxy) do |builder|
          configuration.faraday_builder&.call(builder)
          builder.response :raise_error
          builder.options.merge! faraday_opts
          builder.headers[:user_agent] = "sentry-ruby/#{Sentry::VERSION}"
          builder.adapter(*adapter)
        end
      end

      # TODO: deprecate and replace where possible w/Faraday Builder
      def faraday_opts
        [:timeout, :open_timeout].each_with_object({}) do |opt, memo|
          memo[opt] = configuration.public_send(opt) if configuration.public_send(opt)
        end
      end

      def ssl_configuration
        (configuration.ssl || {}).merge(
          :verify => configuration.ssl_verification,
          :ca_file => configuration.ssl_ca_file
        )
      end
    end
  end
end
