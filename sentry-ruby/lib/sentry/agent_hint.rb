# frozen_string_literal: true

require "open3"
require "rbconfig"

module Sentry
  # Points a coding agent at SETUP_CHECKLIST.md while it sets up Sentry and
  # leaves tracing or logs off. People running the app never see it.
  # @!visibility private
  class AgentHint
    CHECKLIST_PATH = File.expand_path("SETUP_CHECKLIST.md", __dir__)

    # AI_AGENT is the cross-tool convention; the rest cover agents that don't set it.
    AGENT_ENV_VARS = %w[CLAUDECODE CODEX_THREAD_ID CODEX_SANDBOX CURSOR_AGENT GEMINI_CLI].freeze

    # How long after the last change to the file that calls Sentry.init the setup
    # counts as in progress. Without git we can't tell whose change it is, so it's shorter.
    SETUP_WINDOW = 60 * 60
    SETUP_WINDOW_WITHOUT_GIT = 10 * 60

    # Say what Sentry won't show, not which settings are off. An agent that sees
    # the setting names doesn't open the checklist.
    NOT_SHOWN = { tracing: "the request trace around them", logs: "its logs" }.freeze

    @mutex = Mutex.new
    @registered = false
    @hint = nil

    class << self
      # Called by Sentry.init with the location that called it. The hint prints at
      # exit, unless an integration takes it earlier.
      def register(config, caller_location)
        init_file = caller_location&.absolute_path || caller_location&.path
        return if @registered || init_file.nil? || external_source?(init_file) || !coding_agent?

        hint = new(config, init_file)
        return unless hint.applies?

        @mutex.synchronize do
          return if @registered

          @registered = true
          @hint = hint
        end

        pid = Process.pid
        at_exit do
          # Forked workers inherit at_exit blocks, so only the process that called init prints.
          next unless Process.pid == pid

          print_hint(config)
        end
      rescue StandardError => e
        # Best effort: the hint must never break Sentry.init.
        log_failure(config, e)
      end

      # Returns the hint once, or nil when there's nothing to show.
      def take
        hint = @mutex.synchronize { @hint.tap { @hint = nil } }
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

      private

      def print_hint(config)
        message = take
        return unless message

        # Piped stdout is only flushed at exit. Flush it first so the hint stays
        # last for agents that cut the output with `| tail`.
        $stdout.flush
        # Not Kernel#warn: it prints nothing when warnings are off (ruby -W0).
        $stderr.puts(message)
      rescue StandardError => e
        log_failure(config, e)
      end

      # An installed gem or tool that calls Sentry.init itself isn't the user's app,
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

      def log_failure(config, error)
        config.sdk_logger&.debug(LOGGER_PROGNAME) { "Skipped the coding agent hint: #{error.class}: #{error.message}" }
      rescue StandardError
        nil
      end
    end

    def initialize(config, init_file)
      @config = config
      @init_file = File.expand_path(init_file)
    end

    def applies?
      @config.dsn && !@config.agent_setup_complete && missing.any? && changed_within?(SETUP_WINDOW)
    end

    def message
      return unless setup_in_progress?

      "[sentry] Sentry will get errors from this app but not #{missing.map { |product| NOT_SHOWN[product] }.join(", or ")}. " \
        "If you're setting up Sentry, check the setup against Sentry's official setup checklist. If you leave " \
        "it as is, tell the user. The checklist is included in the sentry-ruby gem you installed: " \
        "#{CHECKLIST_PATH} (hide with SENTRY_AGENT_HINTS=0)"
    end

    private

    def missing
      @missing ||= NOT_SHOWN.keys.reject { |product| enabled?(product) }
    end

    def enabled?(product)
      case product
      when :tracing
        # Configuration#validate already rejects a non-numeric rate.
        !@config.traces_sampler.nil? || @config.traces_sample_rate.to_f.positive?
      when :logs
        # Rails.logger is a ::Logger too, so the :logger patch covers Rails apps.
        @config.enabled_patches.include?(:logger)
      end
    end

    def changed_within?(seconds)
      Time.now - File.mtime(@init_file) <= seconds
    rescue SystemCallError
      false
    end

    # Whether this user changed the file a short time ago. A checkout or a
    # teammate's commit also gives the file a new mtime, so ask git.
    def setup_in_progress?
      status = git("status", "--porcelain", "--", @init_file)
      return changed_within?(SETUP_WINDOW_WITHOUT_GIT) if status.nil?
      return true unless status.empty?

      committer = git("log", "-1", "--since=#{SETUP_WINDOW} seconds ago", "--format=%ce", "--", @init_file)
      !committer.to_s.empty? && committer == git("config", "user.email")
    end

    # Returns nil when git isn't installed or the file isn't in a repo. Read only:
    # no index lock, since the agent may be running git at the same time, and no
    # fsmonitor, which would run a command configured in the repo.
    # Open3 leaves the app's $? alone.
    def git(*args)
      output, status = Open3.capture2(
        "git", "--no-optional-locks", "-c", "core.fsmonitor=false", *args,
        chdir: File.dirname(@init_file), err: File::NULL
      )
      output.strip if status.success?
    rescue SystemCallError
      nil
    end
  end
end
