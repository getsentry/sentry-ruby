require_relative 'helper'

module SentryExcludedModule; end
class SentryExcludedException < RuntimeError; end
class SentryExcludedViaSubclass < SentryExcludedException; end
class ExcludedViaExtend < RuntimeError
  extend SentryExcludedModule
end
class DontCaptureMeBro < RuntimeError; end

class ConfigurationTest < Minitest::Spec
  describe "is initialized with certain values" do
    describe "hostname resolution" do
      it "resolves a hostname via sys_command" do
        Raven.stub(:sys_command, "myhost.local") do
          @stubbed_config = Raven::Configuration.new
        end

        assert_equal "myhost.local", @stubbed_config.server_name
      end

      it "falls back to Socket.gethostname if syscommand not available" do
        Raven.stub(:sys_command, nil) do
          Socket.stub(:gethostname, "gethostname") do
            @stubbed_config = Raven::Configuration.new
          end
        end

        assert_equal "gethostname", @stubbed_config.server_name
      end
    end
  end

  describe "setting the server" do
    it "sets a bunch of attributes" do
      @config = Raven::Configuration.new
      @config.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"

      assert_equal "42", @config.project_id
      assert_equal "12345", @config.public_key
      assert_equal "67890", @config.secret_key
      assert_equal "http", @config.scheme
      assert_equal "sentry.localdomain", @config.host
      assert_equal 3000, @config.port
      assert_equal "/sentry", @config.path
      assert_equal "http://sentry.localdomain:3000/sentry", @config.server
    end
  end

  describe "setting the encoding" do
    it "rejects unsupported options" do
      @config = Raven::Configuration.new
      assert_raises(ArgumentError) { @config.encoding = "notarealencoding" }
    end
  end

  describe "setting configs which must be callable" do
    it "rejects uncallable objects" do
      @config = Raven::Configuration.new
      %w(async transport_failure_callback should_capture).each do |m|
        assert_raises(ArgumentError) { @config.public_send("#{m}=", "not_callable") }
      end
    end
  end

  it "allows hash-like access" do
    @config = Raven::Configuration.new
    assert @config[:ssl_verification]
    assert @config["ssl_verification"]
  end

  it "converts current environment into a string" do
    @config = Raven::Configuration.new
    @config.current_environment = :staging
    assert_equal "staging", @config.current_environment
  end

  describe "capture_allowed?" do
    before do
      @valid_config = Raven::Configuration.new(:dsn => "http://12345:67890@sentry.localdomain:3000/sentry/42")
    end

    it "returns true if DSN is set" do
      assert @valid_config.capture_allowed?
    end

    it "checks if DSN is present" do
      @config = Raven::Configuration.new
      refute @config.capture_allowed?
      assert_equal ["DSN not set"], @config.errors
    end

    it "checks if DSN is valid" do
      @valid_config.dsn = "aaa"
      refute @valid_config.capture_allowed?
      assert_equal ["No host specified", "No public_key specified", "No secret_key specified", "No project_id specified"], @valid_config.errors
    end

    it "checks if capture is allowed in environment" do
      @valid_config.environments = ["not_this_one"]
      refute @valid_config.capture_allowed?
      assert_equal ["Not configured to send/capture in environment 'test'"], @valid_config.errors
    end

    it "checks if given object is a Raven::Error" do
      refute @valid_config.capture_allowed?(Raven::Error.new)
      assert_equal ["Refusing to capture Raven error: #<Raven::Error: Raven::Error>"], @valid_config.errors
    end

    it "checks if given object is an excluded exception" do
      @valid_config.excluded_exceptions << SentryExcludedException
      refute @valid_config.capture_allowed?(SentryExcludedException.new)
      assert_equal ["User excluded error: #<SentryExcludedException: SentryExcludedException>"], @valid_config.errors
    end

    it "checks if given object is subclassed from an excluded exception" do
      @valid_config.excluded_exceptions << SentryExcludedViaSubclass
      refute @valid_config.capture_allowed?(SentryExcludedViaSubclass.new)
      assert_equal ["User excluded error: #<SentryExcludedViaSubclass: SentryExcludedViaSubclass>"], @valid_config.errors
    end

    it "works when provided a string rather than a class" do
      @valid_config.excluded_exceptions << "SentryExcludedViaSubclass"
      refute @valid_config.capture_allowed?(SentryExcludedViaSubclass.new)
      assert_equal ["User excluded error: #<SentryExcludedViaSubclass: SentryExcludedViaSubclass>"], @valid_config.errors
    end

    it "checks if given object is an excluded module" do
      skip "This never actually worked"
      @valid_config.excluded_exceptions << SentryExcludedModule
      refute @valid_config.capture_allowed?(ExcludedViaExtend.new)
      assert_equal ["User excluded error: #<ExcludedViaExtend: ExcludedViaExtend>"], @valid_config.errors
    end

    it "checks if object is allowed by the should_capture callback" do
      @valid_config.should_capture = ->(e) { e == DontCaptureMeBro }
      refute @valid_config.capture_allowed?(DontCaptureMeBro.new)
      assert_equal ["should_capture returned false"], @valid_config.errors
    end

    it "sets an error message" do
      @valid_config.dsn = "http://notavalid.com/dsn"
      @valid_config.capture_allowed?
      assert_equal "No public_key specified, no secret_key specified, no project_id specified", @valid_config.error_messages
    end
  end
end
