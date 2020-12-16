module Sentry
  class RequestInterface
    def from_rack(env_hash)
      req = ::Rack::Request.new(env_hash)

      if Sentry.configuration.send_default_pii
        self.data = read_data_from(req)
        self.cookies = req.cookies
      else
        # need to completely wipe out ip addresses
        IP_HEADERS.each { |h| env_hash.delete(h) }
      end

      self.url = req.scheme && req.url.split('?').first
      self.method = req.request_method
      self.query_string = req.query_string

      self.headers = format_headers_for_sentry(env_hash)
      self.env     = format_env_for_sentry(env_hash)
    end
  end
end
