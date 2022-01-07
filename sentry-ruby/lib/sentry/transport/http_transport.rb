# frozen_string_literal: true

require 'faraday'
require 'zlib'

module Sentry
  class HTTPTransport < Transport
    GZIP_ENCODING = "gzip"
    GZIP_THRESHOLD = 1024 * 30
    CONTENT_TYPE = 'application/x-sentry-envelope'

    DEFAULT_DELAY = 60
    RETRY_AFTER_HEADER = "retry-after"
    RATE_LIMIT_HEADER = "x-sentry-rate-limits"

    attr_reader :conn

    def initialize(*args)
      super
      @conn = set_conn
      @endpoint = @dsn.envelope_endpoint
    end

    def send_data(data)
      encoding = ""

      if should_compress?(data)
        data = Zlib.gzip(data)
        encoding = GZIP_ENCODING
      end

      response = conn.post @endpoint do |req|
        req.headers['Content-Type'] = CONTENT_TYPE
        req.headers['Content-Encoding'] = encoding
        req.headers['X-Sentry-Auth'] = generate_auth_header
        req.body = data
      end

      if has_rate_limited_header?(response.headers)
        handle_rate_limited_response(response.headers)
      end
    rescue Faraday::Error => e
      error_info = e.message

      if e.response
        if e.response[:status] == 429
          handle_rate_limited_response(e.response[:headers])
        else
          error_info += "\nbody: #{e.response[:body]}"
          error_info += " Error in headers is: #{e.response[:headers]['x-sentry-error']}" if e.response[:headers]['x-sentry-error']
        end
      end

      raise Sentry::ExternalError, error_info
    end

    private

    def has_rate_limited_header?(headers)
      headers[RETRY_AFTER_HEADER] || headers[RATE_LIMIT_HEADER]
    end

    def handle_rate_limited_response(headers)
      rate_limits =
        if rate_limits = headers[RATE_LIMIT_HEADER]
          parse_rate_limit_header(rate_limits)
        elsif retry_after = headers[RETRY_AFTER_HEADER]
          # although Sentry doesn't send a date string back
          # based on HTTP specification, this could be a date string (instead of an integer)
          retry_after = retry_after.to_i
          retry_after = DEFAULT_DELAY if retry_after == 0

          { nil => Time.now + retry_after }
        else
          { nil => Time.now + DEFAULT_DELAY }
        end

      rate_limits.each do |category, limit|
        if current_limit = @rate_limits[category]
          if current_limit < limit
            @rate_limits[category] = limit
          end
        else
          @rate_limits[category] = limit
        end
      end
    end

    def parse_rate_limit_header(rate_limit_header)
      time = Time.now

      result = {}

      limits = rate_limit_header.split(",")
      limits.each do |limit|
        next if limit.nil? || limit.empty?

        begin
          retry_after, categories = limit.strip.split(":").first(2)
          retry_after = time + retry_after.to_i
          categories = categories.split(";")

          if categories.empty?
            result[nil] = retry_after
          else
            categories.each do |category|
              result[category] = retry_after
            end
          end
        rescue StandardError
        end
      end

      result
    end

    def should_compress?(data)
      @transport_configuration.encoding == GZIP_ENCODING && data.bytesize >= GZIP_THRESHOLD
    end

    def set_conn
      server = @dsn.server

      log_debug("Sentry HTTP Transport connecting to #{server}")

      Faraday.new(server, :ssl => ssl_configuration, :proxy => @transport_configuration.proxy) do |builder|
        builder.response :raise_error
        builder.options.merge! faraday_opts
        builder.headers[:user_agent] = "sentry-ruby/#{Sentry::VERSION}"
        builder.adapter(Faraday.default_adapter)
      end
    end

    # TODO: deprecate and replace where possible w/Faraday Builder
    def faraday_opts
      [:timeout, :open_timeout].each_with_object({}) do |opt, memo|
        memo[opt] = @transport_configuration.public_send(opt) if @transport_configuration.public_send(opt)
      end
    end

    def ssl_configuration
      {
        verify: @transport_configuration.ssl_verification,
        ca_file: @transport_configuration.ssl_ca_file
      }.merge(@transport_configuration.ssl || {})
    end
  end
end
