module Sentry
  class RequestInterface < Interface
    attr_accessor :url, :method, :data, :query_string, :cookies, :headers, :env

    def initialize(*arguments)
      self.headers = {}
      self.env = {}
      self.cookies = nil
      super(*arguments)
    end
  end
end
