module Raven
  class Context
    def self.current
      Thread.current[:sentry_context] ||= new
    end
    
    def self.clear!
      Thread.current[:sentry_context] = nil
    end
    
    attr_reader :extra, :tags, :user
    
    def initialize
      @extra  = {}
      @tags   = {}
      @user   = {}
    end
  end
end
