require 'raven/interfaces'

module Raven
  class HttpInterface < Interface
    name 'request'
    attr_accessor :url
    attr_accessor :method
    attr_accessor :data
    attr_accessor :query_string
    attr_accessor :cookies
    attr_accessor :headers
    attr_accessor :env

    def initialize(*arguments)
      self.headers = {}
      self.env = {}
      self.cookies = nil
      super(*arguments)
    end

    def from_rack(env)
      req = ::Rack::Request.new(env)
      self.url = req.scheme && req.url.split('?').first
      self.method = req.request_method
      self.query_string = req.query_string
      server_protocol = env['SERVER_PROTOCOL']
      env.each_pair do |key, value|
        key = key.to_s #rack env can contain symbols
        next unless key.upcase == key # Non-upper case stuff isn't either
        # Rack adds in an incorrect HTTP_VERSION key, which causes downstream
        # to think this is a Version header. Instead, this is mapped to
        # env['SERVER_PROTOCOL']. But we don't want to ignore a valid header
        # if the request has legitimately sent a Version header themselves.
        # See: https://github.com/rack/rack/blob/028438f/lib/rack/handler/cgi.rb#L29
        next if key == 'HTTP_VERSION' and value == server_protocol
        if key.start_with?('HTTP_')
          # Header
          http_key = key[5..key.length - 1].split('_').map(&:capitalize).join('-')
          self.headers[http_key] = value.to_s
        elsif %w(CONTENT_TYPE CONTENT_LENGTH).include? key
          self.headers[key.capitalize] = value.to_s
        elsif %w(REMOTE_ADDR SERVER_NAME SERVER_PORT).include? key
          # Environment
          self.env[key] = value.to_s
        end
      end

      self.data =
        if req.form_data?
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
