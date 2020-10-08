require "uri"

module Sentry
  class DSN
    attr_reader :scheme, :project_id, :public_key, :secret_key, :host, :port, :path

    def initialize(dsn_string)
      @raw_value = dsn_string

      uri = URI.parse(dsn_string)
      uri_path = uri.path.split('/')

      if uri.user
        # DSN-style string
        @project_id = uri_path.pop
        @public_key = uri.user
        @secret_key = !(uri.password.nil? || uri.password.empty?) ? uri.password : nil
      end

      @scheme = uri.scheme
      @host = uri.host
      @port = uri.port if uri.port
      @path = uri_path.join('/')
    end

    def valid?
      %w(host path public_key project_id).all? { |k| public_send(k) }
    end

    def to_s
      @raw_value
    end

    def server
      server = "#{scheme}://#{host}"
      server += ":#{port}" unless port == { 'http' => 80, 'https' => 443 }[scheme]
      server += path
      server
    end
  end
end
