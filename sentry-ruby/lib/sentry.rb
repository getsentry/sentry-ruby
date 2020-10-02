require "sentry/core_ext/object/deep_dup"
require "sentry/configuration"
require "sentry/logger"
require "sentry/event"
require "sentry/hub"

module Sentry
  class Error < StandardError
  end

  def self.sys_command(command)
    result = `#{command} 2>&1` rescue nil
    return if result.nil? || result.empty? || ($CHILD_STATUS && $CHILD_STATUS.exitstatus != 0)

    result.strip
  end
end
