require "sentry/breadcrumb_buffer"

module Sentry
  class Scope
    attr_accessor :transactions, :extra, :rack_env, :tags, :user, :level, :breadcrumbs

    def initialize
      self.breadcrumbs = BreadcrumbBuffer.new
      self.extra = { :server => { :os => self.class.os_context, :runtime => self.class.runtime_context } }
      self.rack_env = nil
      self.tags = {}
      self.user = {}
      self.level = :error
      self.transactions = []
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
          version: RUBY_DESCRIPTION || Sentry.sys_command("ruby -v")
        }
      end
    end

  end
end
