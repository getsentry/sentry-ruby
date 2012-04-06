require 'uri'

module Raven

  class Client

    attr_reader :server, :public_key, :secret_key, :project_id

    def initialize(dsn, options={})
      if options.empty? && dsn.is_a?(Hash)
        dsn, options = nil, dsn
      end
      dsn ||= options[:dsn]
      dsn ||= ENV['SENTRY_DSN']
      if dsn && !dsn.empty?
        uri = URI::parse(dsn)
        uri_path = uri.path.split('/')
        options[:project_id] = uri_path.pop
        options[:server] = "#{uri.scheme}://#{uri.host}"
        options[:server] << ":#{uri.port}" unless uri.port == {"http"=>80,"https"=>443}[uri.scheme]
        options[:server] << uri_path.join('/')
        options[:public_key] = uri.user
        options[:secret_key] = uri.password
      end
      @server = options[:server]
      @public_key = options[:public_key]
      @secret_key = options[:secret_key]
      @project_id = options[:project_id]
    end

  end

end
