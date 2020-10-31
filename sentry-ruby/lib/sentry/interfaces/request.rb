module Sentry
  class RequestInterface < Interface
    attr_accessor :url, :method, :data, :query_string, :cookies, :headers, :env

    def initialize
      self.headers = {}
      self.env = {}
      self.cookies = nil
    end
  end
end
