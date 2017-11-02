require 'rbconfig'

module Raven
  class Context
    def self.current
      Thread.current[:sentry_context] ||= new
    end

    def self.clear!
      Thread.current[:sentry_context] = nil
    end

    attr_accessor :transaction, :extra, :rack_env, :tags, :user

    def initialize
      self.rack_env = nil
      self.tags = {}
      self.user = {}
      self.transaction = []
    end

    def extra
      @extra ||= {}
      unless @extra[:server]
        @extra[:server] = { :os => server_os, :runtime => runtime }
      end
      @extra
    end

    class << self
      def sys
        @sys = Raven::System.new
      end

      # TODO: reduce to uname -svra
      def os_context
        @os_context ||= {
          :name => sys.command("uname -s") || RbConfig::CONFIG["host_os"],
          :version => sys.command("uname -v"),
          :build => sys.command("uname -r"),
          :kernel_version => sys.command("uname -a") || sys.command("ver") # windows
        }
      end

      def runtime_context
        @runtime_context ||= {
          :name => Kernel.const_defined?(:RUBY_ENGINE) ? RUBY_ENGINE : RbConfig::CONFIG["ruby_install_name"],
          :version => Kernel.const_defined?(:RUBY_DESCRIPTION) ? RUBY_DESCRIPTION : sys.command("ruby -v")
        }
      end
    end

    private

    def server_os
      @server_os ||= self.class.os_context
    end

    def runtime
      @runtime ||= self.class.runtime_context
    end
  end
end
