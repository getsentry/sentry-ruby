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
      self.os = self.class.os_context
      self.rack_env = nil
      self.runtime = self.class.runtime_context
      self.tags = {}
      self.user = {}
    end

    class << self
      def os_context
        @os_context ||= {
          "name" => Raven.sys_command("uname -s") || RbConfig::CONFIG["host_os"],
          "version" => Raven.sys_command("uname -v"),
          "build" => Raven.sys_command("uname -r"),
          "kernel_version" => Raven.sys_command("uname -a", "ver")
        }
      end

      def runtime_context
        @runtime_context ||= {
          "name" => RbConfig::CONFIG["ruby_install_name"],
          "version" => Raven.sys_command("ruby -v")
        }
      end
    end
  end
end
