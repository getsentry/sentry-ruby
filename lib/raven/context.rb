require 'rbconfig'

module Raven
  class Context
    def self.current
      Thread.current[:sentry_context] ||= new
    end

    def self.clear!
      Thread.current[:sentry_context] = nil
    end

    attr_accessor :extra, :server_os, :rack_env, :runtime, :tags, :user

    def initialize
      self.server_os = self.class.os_context
      self.runtime = self.class.runtime_context
      self.extra = { :server => { :os => server_os, :runtime => runtime } }
      self.rack_env = nil
      self.tags = {}
      self.user = {}
    end

    class << self
      def os_context
        @os_context ||= {
          :name => Raven.sys_command("uname -s") || RbConfig::CONFIG["host_os"],
          :version => Raven.sys_command("uname -v"),
          :build => Raven.sys_command("uname -r"),
          :kernel_version => Raven.sys_command("uname -a") || Raven.sys_command("ver") # windows
        }
      end

      def runtime_context
        @runtime_context ||= {
          :name => RbConfig::CONFIG["ruby_install_name"],
          :version => Raven.sys_command("ruby -v")
        }
      end
    end
  end
end
