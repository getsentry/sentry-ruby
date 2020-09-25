# typed: false
require "sentry/breadcrumb_buffer"

module Sentry
  class Scope
    attr_accessor :transactions, :extra, :rack_env, :tags, :user, :level, :breadcrumbs, :fingerprint

    def initialize
      self.breadcrumbs = BreadcrumbBuffer.new
      self.extra = { :server => { :os => self.class.os_context, :runtime => self.class.runtime_context } }
      self.rack_env = nil
      self.tags = {}
      self.user = {}
      self.level = :error
      self.fingerprint = []
      self.transactions = []
    end

    def apply_to_event(event)
      event.tags = tags.merge(event.tags)
      event.user = user.merge(event.user)
      event.extra = extra.merge(event.extra)
      event.fingerprint = fingerprint
      event.level ||= level
      event.transaction = transactions.last
      event.breadcrumbs = breadcrumbs
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
