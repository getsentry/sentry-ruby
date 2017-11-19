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

# These all require mocks or stubs
class TestSystemConfiguration < Raven::ThreadUnsafeTest
  # it "detects release from git" do
  #   sys = Minitest::Mock.new
  #   sys.expect()
  # end
  #
  # it "detects release from Capistrano" do
  #
  # end
  #
  # it "detects release from Heroku" do
  #
  # end
end
