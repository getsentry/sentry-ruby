require "test_helper"

class TestConfiguration < Raven::Test
  def setup
    @configuration = Raven::Configuration.new
  end

  it "detects the project root" do
    assert_equal Dir.pwd, @configuration.project_root
  end

  # detects hostname

  it "should set some attributes when server is set" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"

    assert_equal "42",    @configuration.project_id
    assert_equal "12345", @configuration.public_key
    assert_equal "67890", @configuration.secret_key
    assert_equal "http",  @configuration.scheme
    assert_equal 3000,    @configuration.port
    assert_equal "/sentry",            @configuration.path
    assert_equal "sentry.localdomain", @configuration.host

    assert_equal "http://sentry.localdomain:3000/sentry", @configuration.server
  end

  it "sets encoding" do
    @configuration.encoding = "json"
    assert_equal "json", @configuration.encoding
    assert_raises(ArgumentError) { @configuration.encoding = "flurp" }
  end

  it "sets async" do
    myproc = proc { |_e| :ok }
    @configuration.async = myproc

    assert_equal myproc, @configuration.async
    assert_raises(ArgumentError) { @configuration.async = 1 }
  end

  it "sets transport_failure_callback" do
    myproc = proc { |_evt, _e| :ok }
    @configuration.transport_failure_callback = myproc

    assert_equal myproc, @configuration.transport_failure_callback
    assert_raises(ArgumentError) { @configuration.transport_failure_callback = 1 }
  end

  it "sets should_capture" do
    myproc = proc { |_e| :ok }
    @configuration.should_capture = myproc

    assert_equal myproc, @configuration.should_capture
    assert_raises(ArgumentError) { @configuration.should_capture = 1 }
  end

  it "converts current environment to string" do
    @configuration.current_environment = :symbol
    assert_equal "symbol", @configuration.current_environment
  end

  it "converts project root to string" do
    @configuration.project_root = :symbol
    assert_equal "symbol", @configuration.project_root
  end

  it "checks if capture is allowed" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"

    assert @configuration.capture_allowed?("test message")
    assert @configuration.capture_allowed?(RuntimeError.new("Boom!"))
  end

  it "rejects if the DSN is not set" do
    refute @configuration.capture_allowed?("test message")
    assert_equal "DSN not set", @configuration.error_messages
  end

  it "rejects if the DSN is partially set" do
    @configuration.server = "http://12345:@sentry.localdomain:3000/sentry/42"

    refute @configuration.capture_allowed?("test message")
    assert_equal "No secret_key specified", @configuration.error_messages
  end

  it "rejects if we are not in the correct env" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.environments = ["foo"]
    @configuration.current_environment = "bar"

    refute @configuration.capture_allowed?("test message")
    assert_equal "Not configured to send/capture in environment 'bar'", @configuration.error_messages
  end

  it "rejects if the should capture callback returns false" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.should_capture = proc { |_e| false }

    refute @configuration.capture_allowed?("test message")
    assert_equal "should_capture returned false", @configuration.error_messages
  end

  # sample_allowed
  it "samples exceptions" do
    Kernel.srand 3
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.sample_rate = 0.5

    refute @configuration.capture_allowed?("test message")
    assert_equal "Excluded by random sample", @configuration.error_messages
  end

  it "doesnt capture Raven Errors, and fails loudly" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    strio = StringIO.new
    @configuration.logger = Logger.new(strio)

    refute @configuration.capture_allowed?(Raven::Error.new("Nope"))
    assert_equal "This is an internal Raven error", @configuration.error_messages
    assert_match "Raven has had an internal error!", strio.string
    assert_match "FATAL", strio.string
  end

  it "doesnt capture excluded errors" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.excluded_exceptions = [SyntaxError]

    refute @configuration.capture_allowed?(SyntaxError.new)
    assert_equal "SyntaxError excluded from capture", @configuration.error_messages
  end

  it "works with invalid exclusions" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.excluded_exceptions = [nil, 1, {}]

    assert @configuration.capture_allowed?("test message")
  end

  it "works with strings" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"

    @configuration.excluded_exceptions = ["::SyntaxError"]
    refute @configuration.capture_allowed?(SyntaxError.new)
    assert_equal "SyntaxError excluded from capture", @configuration.error_messages

    @configuration.excluded_exceptions = ["SyntaxError"]
    refute @configuration.capture_allowed?(SyntaxError.new)
    assert_equal "SyntaxError excluded from capture", @configuration.error_messages
  end

  it "works with subclasses" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.excluded_exceptions = [ScriptError]
    refute @configuration.capture_allowed?(NotImplementedError.new)
    assert_equal "NotImplementedError excluded from capture", @configuration.error_messages
  end

  module MyModule
  end
  class TestExc
    include MyModule
  end

  it "works with included modules" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.excluded_exceptions = [MyModule]
    refute @configuration.capture_allowed?(TestExc.new)

    assert_equal "TestConfiguration::TestExc excluded from capture", @configuration.error_messages
  end

  it "works with classes that dont exist" do
    @configuration.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"
    @configuration.excluded_exceptions = ["ThisDoesNotExist"]

    assert @configuration.capture_allowed?("test message")
  end
end

class TestSystemConfiguration < Raven::Test
  def setup
    @configuration = Raven::Configuration.new
    @sysmock = Minitest::Mock.new
    @configuration.instance_variable_set(:@sys, @sysmock)
  end

  it "returns nil if it cannot detect release" do
    @sysmock.expect(:git_available?, false)
    @sysmock.expect(:running_on_heroku?, false)
    refute @configuration.send(:detect_release)
  end

  it "detects release from git" do
    @sysmock.expect(:git_available?, true)
    @sysmock.expect(:command, "0057adf", ["git rev-parse --short HEAD"])

    assert_equal "0057adf", @configuration.send(:detect_release)
  end

  it "detects release from Capistrano (oldstyle)" do
    @sysmock.expect(:git_available?, false)
    @sysmock.expect(:cap_revision, "8b42a3e", [String])
    @configuration.project_root = Dir.pwd + "/test/support/capistrano"

    assert_equal "8b42a3e", @configuration.send(:detect_release)
  end

  it "detects release from Capistrano (newstyle)" do
    @sysmock.expect(:git_available?, false)
    @sysmock.expect(:cap_revision, "8b42a3e", [String])
    @configuration.project_root = Dir.pwd + "/test/support/capistrano/root"

    assert_equal "8b42a3e", @configuration.send(:detect_release)
  end
end

# All depend on certain things in ENV
class TestHerokuConfiguration < Raven::ThreadUnsafeTest
  def setup
    @configuration = Raven::Configuration.new
    @sysmock = Minitest::Mock.new
    @configuration.instance_variable_set(:@sys, @sysmock)
  end

  it "detects release from Heroku" do
    ENV['HEROKU_SLUG_COMMIT'] = "aaaaaa"
    @sysmock.expect(:git_available?, true) # Git is available on Heroku, but fails
    @sysmock.expect(:command, nil, ["git rev-parse --short HEAD"])
    @sysmock.expect(:running_on_heroku?, true)

    assert_equal "aaaaaa", @configuration.send(:detect_release)

    ENV['HEROKU_SLUG_COMMIT'] = nil
  end
end

class TestENVConfiguration < Raven::ThreadUnsafeTest
  def setup
    ENV['SENTRY_CURRENT_ENV'] = 'set-with-sentry-current-env'
    ENV['RAILS_ENV'] = 'set-with-rails-env'
    ENV['RACK_ENV'] = 'set-with-rack-env'
  end

  def teardown
    ENV['SENTRY_CURRENT_ENV'] = nil
    ENV['RAILS_ENV'] = nil
    ENV['RACK_ENV'] = nil
  end

  it "uses SENTRY_CURRENT_ENV to set the current environment" do
    configuration = Raven::Configuration.new
    assert_equal 'set-with-sentry-current-env', configuration.current_environment
  end

  it "uses RAILS_ENV to set the current environment" do
    ENV['SENTRY_CURRENT_ENV'] = nil

    configuration = Raven::Configuration.new
    assert_equal 'set-with-rails-env', configuration.current_environment
  end

  it "uses RACK_ENV to set the current environment" do
    ENV['SENTRY_CURRENT_ENV'] = nil
    ENV['RAILS_ENV'] = nil

    configuration = Raven::Configuration.new
    assert_equal 'set-with-rack-env', configuration.current_environment
  end
end
