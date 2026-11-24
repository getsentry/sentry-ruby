# frozen_string_literal: true

require "open3"
require "rbconfig"

module Sentry
  # Points a coding agent at SETUP_CHECKLIST.md while it sets up Sentry and
  # leaves tracing or logs off. People running the app never see it.
  #
  # Best effort throughout: failures are logged at debug level and swallowed, so
  # the hint can never break Sentry.init, a Rails boot or the app's exit status.
  # @!visibility private
  class AgentHint
    CHECKLIST_PATH = File.expand_path("SETUP_CHECKLIST.md", __dir__)

    # AI_AGENT is the cross-tool convention; the rest cover agents that don't set it.
    AGENT_ENV_VARS = %w[CLAUDECODE CODEX_THREAD_ID CODEX_SANDBOX CURSOR_AGENT GEMINI_CLI].freeze

    # How long after the last change to the file that calls Sentry.init the setup
    # counts as in progress. Without git we can't tell whose change it is, so it's shorter.
    SETUP_WINDOW = 60 * 60
    SETUP_WINDOW_WITHOUT_GIT = 10 * 60

    # Per git call. A slow repo must not hold up the app's exit or a Rails boot.
    GIT_TIMEOUT = 2
    # Its own process group, so a timeout also kills anything git started.
    GIT_SPAWN_OPTIONS = Gem.win_platform? ? {} : { pgroup: true }

    class GitTimeout < StandardError; end

    # Say what Sentry won't show, not which settings are off. An agent that sees
    # the setting names doesn't open the checklist.
    NOT_SHOWN = { tracing: "the request trace around them", logs: "its logs" }.freeze

    @mutex = Mutex.new
    @registered = false
    @hint = nil

    class << self
      # Called by Sentry.init. The hint is shown at exit, unless an integration
      # shows it earlier.
      def register(config, caller_location)
        @init = [config, caller_location&.absolute_path || caller_location&.path]
        arm
      end

      # Spring runs Sentry.init once in its preloaded app, with the ENV Spring was
      # started with, then forks each command with the caller's ENV. Decide again
      # in the fork, so a command run by an agent shows the hint.
      def after_fork
        @mutex = Mutex.new
        @registered = false
        @hint = nil
        arm
      end

      def show
        message = take
        return unless message

        # Piped stdout is only flushed at exit. Flush it first so the hint stays
        # last for agents that cut the output with `| tail`.
        $stdout.flush
        # Not Kernel#warn: it prints nothing when warnings are off (ruby -W0).
        $stderr.puts(message)
      rescue StandardError
        # stderr may be closed. An error raised in at_exit would set exit status 1.
        nil
      end

      # Returns the message at most once per process.
      def take
        hint = @mutex.synchronize do
          taken, @hint = @hint, nil
          taken
        end
        hint&.message
      end

      def coding_agent?
        return false if Utils::EnvHelper.env_to_bool(ENV["CI"])
        # Only an explicit falsy value turns hints off, so SENTRY_AGENT_HINTS= keeps them on.
        return false if Utils::EnvHelper.env_to_bool(ENV["SENTRY_AGENT_HINTS"], strict: true) == false

        # An empty AI_AGENT doesn't count, so it can't hide the agent-specific vars below.
        ai_agent = ENV["AI_AGENT"].to_s
        return Utils::EnvHelper.env_to_bool(ai_agent, strict: true) != false unless ai_agent.empty?

        AGENT_ENV_VARS.any? { |name| !ENV[name].to_s.empty? }
      end

      def log_failure(config, error)
        config&.sdk_logger&.debug(LOGGER_PROGNAME) { "Skipped the coding agent hint: #{error.class}: #{error.message}" }
      rescue StandardError
        nil
      end

      private

      def arm
        config, init_file = @init
        # ENV checks first: outside a coding agent this is the only work done.
        return if config.nil? || @registered || !coding_agent?
        return if init_file.nil? || external_source?(init_file)

        hint = new(config, init_file)
        return unless hint.applies?

        @mutex.synchronize do
          return if @registered

          @registered = true
          @hint = hint
        end

        pid = Process.pid
        at_exit do
          # Forked workers inherit at_exit blocks, so only the process that registered prints.
          show if Process.pid == pid
        end
      rescue StandardError => e
        log_failure(config, e)
      end

      # An installed gem or tool that calls Sentry.init isn't the user's app,
      # even when it was installed a moment ago.
      def external_source?(path)
        path = real_path(path)
        [*Gem.path, RbConfig::CONFIG["rubylibdir"]].compact.any? do |dir|
          path.start_with?(File.join(real_path(dir), ""))
        end
      end

      # Gem dirs and tmp dirs are often symlinks (/var -> /private/var on macOS).
      def real_path(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end
    end

    def initialize(config, init_file)
      @config = config
      @init_file = File.expand_path(init_file)
    end

    # Runs during Sentry.init, so the slower git checks wait for #message.
    def applies?
      @config.dsn && !@config.agent_setup_complete && missing.any? && changed_within?(SETUP_WINDOW)
    end

    def message
      return unless setup_in_progress?

      "[sentry] Sentry will get errors from this app but not #{missing.map { |product| NOT_SHOWN[product] }.join(", or ")}. " \
        "If you're setting up Sentry, check the setup against Sentry's official setup checklist. If you leave " \
        "it as is, tell the user. The checklist is included in the sentry-ruby gem you installed: " \
        "#{CHECKLIST_PATH} (hide with SENTRY_AGENT_HINTS=0)"
    rescue StandardError => e
      self.class.log_failure(@config, e)
      nil
    end

    private

    def missing
      @missing ||= NOT_SHOWN.keys.reject { |product| enabled?(product) }
    end

    def enabled?(product)
      case product
      when :tracing
        !@config.traces_sampler.nil? || @config.traces_sample_rate.to_f.positive?
      when :logs
        # sentry-rails adds config.rails. There, logs means Rails structured logging;
        # the :logger patch would send every Rails.logger line, which is noisy.
        if @config.respond_to?(:rails)
          @config.rails.structured_logging.enabled?
        else
          @config.enabled_patches.include?(:logger)
        end
      end
    end

    def changed_within?(seconds)
      Time.now - File.mtime(@init_file) <= seconds
    rescue SystemCallError
      false
    end

    # Whether this user changed the file recently. A checkout or a teammate's
    # commit also gives the file a new mtime, so ask git.
    def setup_in_progress?
      status = git("status", "--porcelain", "--", @init_file)
      return changed_within?(SETUP_WINDOW_WITHOUT_GIT) if status.nil?
      return true unless status.empty?

      committer = git("log", "-1", "--since=#{SETUP_WINDOW} seconds ago", "--format=%ce", "--", @init_file)
      !committer.to_s.empty? && committer == git("config", "user.email")
    end

    # Returns nil when git isn't installed or the file isn't in a repo, and raises
    # GitTimeout when git is too slow, which skips the hint.
    # --no-optional-locks: the agent may be running git at the same time.
    # core.fsmonitor=false: an fsmonitor would run a command configured in the repo.
    # Open3 leaves the app's $? alone.
    def git(*args)
      Open3.popen2(
        "git", "--no-optional-locks", "-c", "core.fsmonitor=false", *args,
        chdir: File.dirname(@init_file), err: File::NULL, **GIT_SPAWN_OPTIONS
      ) do |stdin, stdout, wait_thread|
        stdin.close
        # Read while waiting, so a full pipe can't stall git until the timeout.
        # Closing stdout after a timeout makes the read raise, which is expected.
        reader = Thread.new do
          Thread.current.report_on_exception = false
          stdout.read
        end

        unless wait_thread.join(GIT_TIMEOUT)
          Process.kill(:KILL, Gem.win_platform? ? wait_thread.pid : -wait_thread.pid)
          raise GitTimeout, "git #{args.first} took over #{GIT_TIMEOUT}s"
        end

        output = reader.value
        output.strip if wait_thread.value.success?
      end
    rescue SystemCallError, IOError
      nil
    end
  end
end
