require 'rbconfig'
require 'etc'

module Raven
  class Context
    def self.current
      Thread.current[:sentry_context] ||= new
    end

    def self.clear!
      Thread.current[:sentry_context] = nil
    end

    attr_accessor :transaction, :extra, :server_os, :rack_env, :runtime, :tags, :user

    def initialize
      self.server_os = self.class.os_context
      self.runtime = self.class.runtime_context
      self.extra = { :server => { :os => server_os, :runtime => runtime } }
      self.rack_env = nil
      self.tags = {}
      self.user = {}
      self.transaction = []
    end

    class << self
      def os_context
        @os_context ||=
          begin
            uname = Etc.uname
            {
              name: uname[:sysname] || RbConfig::CONFIG["host_os"],
              version: uname[:version],
              build: uname[:release],
              kernel_version: uname[:version]
            }
          end
      end

      def runtime_context
        @runtime_context ||= {
          name: RbConfig::CONFIG["ruby_install_name"],
          version: RUBY_DESCRIPTION || Raven.sys_command("ruby -v")
        }
      end
    end
  end
end
