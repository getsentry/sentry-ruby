require 'raven/interfaces'

module Raven

  class HttpInterface < Interface

    name 'sentry.interfaces.Http'
    property :url, :required => true
    property :method, :required => true
    property :data
    property :query_string
    property :cookies
    property :headers
    property :env

    def initialize(*arguments)
      self.headers = {}
      self.env = {}
      super(*arguments)
    end

    def from_rack(env)
      require 'rack'
      req = ::Rack::Request.new(env)
      self.url = req.url.split('?').first
      self.method = req.request_method
      self.query_string = req.query_string
      env.each_pair do |key, value|
        next unless key.upcase == key # Non-upper case stuff isn't either
        if key.start_with?('HTTP_')
          # Header
          http_key = key[5..key.length-1].split('_').map{|s| s.capitalize}.join('-')
          self.headers[http_key] = value.to_s
        else
          # Environment
          self.env[key] = value.to_s
        end
      end
      self.data = if req.form_data?
        req.POST
      elsif req.body
        data = req.body.read
        req.body.rewind
        data
      end
    end

  end

  register_interface :http => HttpInterface

end
