# frozen_string_literal: true

require "spec_helper"
require "open3"
require "stringio"
require "tmpdir"

RSpec.describe Sentry::AgentHint do
  let(:checklist) { described_class::CHECKLIST_PATH }
  let(:app) { File.join(@dir, "app.rb") }
  let(:at_exit_hooks) { [] }

  around do |example|
    names = ["CI", "SENTRY_AGENT_HINTS", "AI_AGENT", *described_class::AGENT_ENV_VARS]
    saved = ENV.to_h.slice(*names)
    names.each { |name| ENV.delete(name) }

    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  ensure
    names.each { |name| ENV.delete(name) }
    ENV.update(saved)
  end

  before do
    described_class.instance_variable_set(:@hint, nil)
    described_class.instance_variable_set(:@registered, false)
    allow(described_class).to receive(:at_exit) { |&hook| at_exit_hooks << hook }
  end

  # Loads a file that calls Sentry.init, the way an app's initializer does.
  def load_app(env, config = "", before_load: nil, path: app)
    ENV.update(env)
    File.write(path, <<~RUBY)
      Sentry.init do |config|
        config.sdk_logger = ::Logger.new(nil)
        config.dsn = #{Sentry::TestHelper::DUMMY_DSN.inspect}
        config.transport.transport_class = Sentry::DummyTransport
        #{config}
      end
    RUBY
    before_load&.call(path)
    load(path)
  end

  # Loads the app and returns what the SDK prints at exit.
  def run_app(...)
    load_app(...)
    capture_stderr { at_exit_hooks.each(&:call) }
  end

  def capture_stderr
    original, $stderr = $stderr, StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  describe "who sees it" do
    {
      { "AI_AGENT" => "claude-code" } => true,
      { "CLAUDECODE" => "1" } => true,
      { "CODEX_THREAD_ID" => "abc" } => true,
      { "CURSOR_AGENT" => "1" } => true,
      {} => false,
      { "AI_AGENT" => "0" } => false,
      { "AI_AGENT" => "claude-code", "CI" => "true" } => false,
      { "CLAUDECODE" => "1", "SENTRY_AGENT_HINTS" => "0" } => false,
      { "CLAUDECODE" => "" } => false,
      { "AI_AGENT" => "", "CLAUDECODE" => "1" } => true,
      { "CI" => "", "CLAUDECODE" => "1" } => true,
      { "CI" => "false", "CLAUDECODE" => "1" } => true,
      { "SENTRY_AGENT_HINTS" => "", "CLAUDECODE" => "1" } => true,
      { "SENTRY_AGENT_HINTS" => "off", "CLAUDECODE" => "1" } => false
    }.each do |env, shown|
      it "is #{"not " unless shown}shown for #{env}" do
        expect(run_app(env).include?(checklist)).to be(shown)
      end
    end
  end

  describe "what it says" do
    {
      "" => "not the request trace around them, or its logs.",
      "config.enabled_patches << :logger" => "not the request trace around them.",
      "config.traces_sample_rate = 0.1" => "not its logs.",
      "config.traces_sampler = ->(_) { 1.0 }" => "not its logs.",
      "config.traces_sample_rate = 0.0" => "not the request trace around them, or its logs."
    }.each do |config, missing|
      it "says what's missing with #{config.inspect}" do
        expect(run_app({ "AI_AGENT" => "claude-code" }, config))
          .to start_with("[sentry] Sentry will get errors from this app but #{missing}")
          .and include(checklist)
      end
    end
  end

  [
    "config.traces_sample_rate = 0.1; config.enabled_patches << :logger",
    "config.agent_setup_complete = true",
    "config.dsn = nil"
  ].each do |config|
    it "is not shown with #{config.inspect}" do
      expect(run_app({ "AI_AGENT" => "claude-code" }, config)).to eq("")
    end
  end

  it "is shown once" do
    load_app({ "AI_AGENT" => "claude-code" })

    expect(run_app({})).to include(checklist)
    expect(at_exit_hooks.size).to eq(1)
  end

  it "isn't printed at exit when an integration took it" do
    load_app({ "AI_AGENT" => "claude-code" })

    expect(described_class.take).to include(checklist)
    expect(described_class.take).to be_nil
    expect(capture_stderr { at_exit_hooks.each(&:call) }).to eq("")
  end

  it "is printed when Ruby warnings are off" do
    load_app({ "AI_AGENT" => "claude-code" })
    verbose, $VERBOSE = $VERBOSE, nil

    expect(capture_stderr { at_exit_hooks.each(&:call) }).to include(checklist)
  ensure
    $VERBOSE = verbose
  end

  it "isn't shown when an installed gem calls Sentry.init" do
    allow(Gem).to receive(:path).and_return([@dir])

    expect(run_app({ "AI_AGENT" => "claude-code" })).to eq("")
  end

  it "runs git without fsmonitor or optional locks" do
    allow(Open3).to receive(:capture2).and_call_original

    run_app({ "AI_AGENT" => "claude-code" })

    expect(Open3).to have_received(:capture2)
      .with("git", "--no-optional-locks", "-c", "core.fsmonitor=false", "status", any_args)
  end

  it "isn't printed by a forked child" do
    load_app({ "AI_AGENT" => "claude-code" })
    allow(Process).to receive(:pid).and_return(Process.pid + 1)

    expect(capture_stderr { at_exit_hooks.each(&:call) }).to eq("")
  end

  describe "only while Sentry is being set up" do
    before { skip("needs git") unless system("git", "--version", out: File::NULL) }

    def git(path, *args, committer: "dev@example.com", date: nil)
      env = {
        "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_COMMITTER_NAME" => "Dev", "GIT_COMMITTER_EMAIL" => committer,
        "GIT_AUTHOR_NAME" => "Dev", "GIT_AUTHOR_EMAIL" => committer
      }
      env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = date if date
      _, status = Open3.capture2e(env, "git", *args, chdir: File.dirname(path))
      raise "git #{args.join(" ")} failed" unless status.success?
    end

    def commit(path, **options)
      git(path, "init", "-q")
      git(path, "config", "user.email", "dev@example.com")
      git(path, "add", File.basename(path))
      git(path, "commit", "-q", "-m", "Set up Sentry", **options)
    end

    def touch(path, minutes_ago)
      File.utime(Time.now - minutes_ago * 60, Time.now - minutes_ago * 60, path)
    end

    def edit_old_commit(path, minutes_ago: 0)
      commit(path, date: "2020-01-01T00:00:00")
      File.write(path, "#{File.read(path)}\n")
      touch(path, minutes_ago)
    end

    {
      "new file, no git repo" => [nil, true],
      "no git repo, changed 20 minutes ago" => [->(path) { touch(path, 20) }, false],
      "uncommitted change" => [->(path) { edit_old_commit(path) }, true],
      "uncommitted change, 20 minutes ago" => [->(path) { edit_old_commit(path, minutes_ago: 20) }, true],
      "uncommitted change, two hours ago" => [->(path) { edit_old_commit(path, minutes_ago: 120) }, false],
      "committed here a moment ago" => [->(path) { commit(path) }, true],
      "a teammate's new commit" => [->(path) { commit(path, committer: "teammate@example.com") }, false],
      "fresh checkout of an old commit" => [->(path) { commit(path, date: "2020-01-01T00:00:00") }, false]
    }.each do |name, (setup, shown)|
      it "is #{"not " unless shown}shown for: #{name}" do
        before_load = setup && ->(path) { instance_exec(path, &setup) }

        expect(run_app({ "AI_AGENT" => "claude-code" }, before_load: before_load).include?(checklist)).to be(shown)
      end
    end
  end

  it "ships the setup checklist with the gem" do
    expect(File.read(checklist)).to include("config.agent_setup_complete = true")
  end
end
