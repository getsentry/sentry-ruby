# frozen_string_literal: true

require "json"

module Sentry
  class RequestInterface < Interface
    REQUEST_ID_HEADERS = %w[action_dispatch.request_id HTTP_X_REQUEST_ID].freeze
    CONTENT_HEADERS = %w[CONTENT_TYPE CONTENT_LENGTH].freeze

    # Regex to detect lowercase chars — match? is allocation-free (no MatchData/String)
    LOWERCASE_PATTERN = /[a-z]/.freeze

    # See Sentry server default limits at
    # https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
    MAX_BODY_LIMIT = 4096 * 4

    # @return [String]
    attr_accessor :url

    # @return [String]
    attr_accessor :method

    # @return [Hash]
    attr_accessor :data

    # @return [String, Hash]
    attr_accessor :query_string

    # @return [Hash]
    attr_accessor :cookies

    # @return [Hash]
    attr_accessor :headers

    # @return [Hash]
    attr_accessor :env

    # @param env [Hash]
    # @param data_collection [DataCollection]
    # @param send_default_pii [Boolean] Deprecated compatibility input, unused.
    # @param rack_env_whitelist [Array]
    # @see Configuration#data_collection
    # @see Configuration#send_default_pii
    # @see Configuration#rack_env_whitelist
    def initialize(env:, data_collection:, rack_env_whitelist:, send_default_pii: nil)
      env = env.dup
      request = ::Rack::Request.new(env)
      query = data_collection.url_query_params.filter(request.GET) rescue nil

      self.method       = request.request_method
      self.url          = request.scheme && request.url.split("?").first
      self.query_string = query unless query&.empty?
      self.cookies      = data_collection.cookies.filter(request.cookies, cookie: true)
      self.data         = read_data_from(request) if data_collection.collect_incoming_http_body?
      self.headers      = filter_and_format_headers(env, data_collection.http_headers.request)
      self.env          = filter_and_format_env(env, data_collection.http_headers.request, rack_env_whitelist)
    end

    private

    def read_data_from(request)
      return "Skipped non-rewindable request body" unless request.body.respond_to?(:rewind)

      if request.form_data?
        DataCollection.filter(request.POST)
      else
        body = request.body.read(MAX_BODY_LIMIT)
        body = Utils::EncodingHelper.encode_to_utf_8(body.to_s)

        if request.media_type == "application/json" || request.media_type&.end_with?("+json")
          parsed_body = JSON.parse(body)
          parsed_body.is_a?(Hash) ? DataCollection.filter(parsed_body) : parsed_body
        else
          body
        end
      end
    rescue JSON::ParserError, IOError => e
      e.message
    ensure
      request.body.rewind if request.body.respond_to?(:rewind)
    end

    def filter_and_format_headers(env, collection)
      env.each_with_object({}) do |(key, value), memo|
        begin
          key = key.to_s # rack env can contain symbols
          next memo["X-Request-Id"] ||= Utils::RequestId.read_from(env) if Utils::RequestId::REQUEST_ID_HEADERS.include?(key)
          next if is_server_protocol?(key, value, env["SERVER_PROTOCOL"])
          next if is_skippable_header?(key)

          # Rack stores headers as HTTP_WHAT_EVER, we need What-Ever
          key = key.delete_prefix("HTTP_")
          key = key.split("_").map(&:capitalize).join("-")

          memo[key] = Utils::EncodingHelper.encode_to_utf_8(value.to_s)
        rescue StandardError => e
          # Rails adds objects to the Rack env that can sometimes raise exceptions
          # when `to_s` is called.
          # See: https://github.com/rails/rails/blob/master/actionpack/lib/action_dispatch/middleware/remote_ip.rb#L134
          Sentry.sdk_logger.warn(LOGGER_PROGNAME) { "Error raised while formatting headers: #{e.message}" }
          next
        end
      end.then do |e|
        collection.filter(e)
      end
    end

    def is_skippable_header?(key)
      key.match?(LOWERCASE_PATTERN) || # lower-case envs aren't real http headers
        !(key.start_with?("HTTP_") || CONTENT_HEADERS.include?(key))
    end

    # In versions < 3, Rack adds in an incorrect HTTP_VERSION key, which causes downstream
    # to think this is a Version header. Instead, this is mapped to
    # env['SERVER_PROTOCOL']. But we don't want to ignore a valid header
    # if the request has legitimately sent a Version header themselves.
    # See: https://github.com/rack/rack/blob/028438f/lib/rack/handler/cgi.rb#L29
    def is_server_protocol?(key, value, protocol_version)
      return false if self.class.rack_3_or_above?

      key == "HTTP_VERSION" && value == protocol_version
    end

    def self.rack_3_or_above?
      return @rack_3_or_above if defined?(@rack_3_or_above)

      @rack_3_or_above = defined?(::Rack) &&
        Gem::Version.new(::Rack.release) >= Gem::Version.new("3.0")
    end

    def filter_and_format_env(env, collection, rack_env_whitelist)
      if rack_env_whitelist.empty?
        env
      else
        env.select do |k, _v|
          rack_env_whitelist.include? k.to_s
        end
      end.then do |e|
        collection.filter(e)
      end
    end
  end
end
