module Raven
  class System
    def command(command)
      result = execute(command) rescue nil
      result.strip!
      return if result.nil? || result.empty? || $CHILD_STATUS.exitstatus != 0
      result
    end

    def git_available?
      File.directory?(".git")
    end

    def running_on_heroku?
      File.directory?("/etc/heroku")
    end

    def cap_revision(path)
      File.readlines(path).last.strip.sub(/.*as release ([0-9]+).*/, '\1') if File.exist?(path)
    end

    def server_name
      running_on_heroku? ? env["DYNO"] : resolve_hostname
    end

    def resolve_hostname
      Socket.gethostname || Socket.gethostbyname(hostname).first
    rescue
      nil
    end

    def current_environment
      env['SENTRY_CURRENT_ENV'] || env['RAILS_ENV'] || env['RACK_ENV'] || 'default'
    end

    private

    def execute(command_str)
      IO.popen(command_str, :err => [:child, :out], &:read)
    end

    def env
      ENV
    end
  end
end
