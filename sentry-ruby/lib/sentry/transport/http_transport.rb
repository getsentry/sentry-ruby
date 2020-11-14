require 'faraday'

module Sentry
  class HTTPTransport < Transport
    attr_reader :conn, :adapter

    def initialize(*args)
      super
      @adapter = @transport_configuration.http_adapter || Faraday.default_adapter
      @conn = set_conn
      @endpoint = @dsn.envelope_endpoint
    end

    def send_data(data, options = {})
      unless configuration.sending_allowed?
        logger.debug(LOGGER_PROGNAME) { "Event not sent: #{configuration.error_messages}" }
      end

      conn.post @endpoint do |req|
        req.headers['Content-Type'] = options[:content_type]
        req.headers['X-Sentry-Auth'] = generate_auth_header
        req.body = data
      end
    rescue Faraday::Error => e
      error_info = e.message

      if e.response
        error_info += "\nbody: #{e.response[:body]}"
        error_info += " Error in headers is: #{e.response[:headers]['x-sentry-error']}" if e.response[:headers]['x-sentry-error']
      end

      raise Sentry::Error, error_info
    end

    private

    def set_conn
      server = @dsn.server

      configuration.logger.debug(LOGGER_PROGNAME) { "Sentry HTTP Transport connecting to #{server}" }

      Faraday.new(server, :ssl => ssl_configuration, :proxy => @transport_configuration.proxy) do |builder|
        @transport_configuration.faraday_builder&.call(builder)
        builder.response :raise_error
        builder.options.merge! faraday_opts
        builder.headers[:user_agent] = "sentry-ruby/#{Sentry::VERSION}"
        builder.adapter(*adapter)
      end
    end

    # TODO: deprecate and replace where possible w/Faraday Builder
    def faraday_opts
      [:timeout, :open_timeout].each_with_object({}) do |opt, memo|
        memo[opt] = @transport_configuration.public_send(opt) if @transport_configuration.public_send(opt)
      end
    end

    def ssl_configuration
      (@transport_configuration.ssl || {}).merge(
        :verify => @transport_configuration.ssl_verification,
        :ca_file => @transport_configuration.ssl_ca_file
      )
    end
  end
end
