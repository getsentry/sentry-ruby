module Raven
  class Context
    def current
      Thread.current[:sentry_context] ||= new
    end
    
    def clear!
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
