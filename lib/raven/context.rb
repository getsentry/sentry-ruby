require 'rbconfig'

module Raven
  class Context
    def self.current
      Thread.current[:sentry_context] ||= new
    end

    def self.clear!
      Thread.current[:sentry_context] = nil
    end

    attr_accessor :extra, :os, :rack_env, :runtime, :tags, :user

    def initialize
      self.extra = {}
      self.os = os_context
      self.rack_env = nil
      self.runtime = runtime_context
      self.tags = {}
      self.user = {}
    end

    private

    def os_context
      {
        "name" => RbConfig::CONFIG["host_os"]
      }
    end

    def runtime_context
      {
        "name" => RbConfig::CONFIG["ruby_install_name"],
        "version" => RbConfig::CONFIG["ruby_version"]
      }
    end
  end
end
