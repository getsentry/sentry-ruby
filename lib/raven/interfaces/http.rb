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
  end

  register_interface :http => HttpInterface
end
