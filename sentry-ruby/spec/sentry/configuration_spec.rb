# frozen_string_literal: true

RSpec.describe Sentry::Configuration do
  describe "#background_worker_threads" do
    it "sets to have of the processors count" do
      allow_any_instance_of(Sentry::Configuration).to receive(:processor_count).and_return(8)
      expect(subject.background_worker_threads).to eq(4)
    end

    it "sets to 1 with only 1 processor" do
      allow_any_instance_of(Sentry::Configuration).to receive(:processor_count).and_return(1)
      expect(subject.background_worker_threads).to eq(1)
    end
  end

  describe "#csp_report_uri" do
    it "returns nil if the dsn is not present" do
      expect(subject.csp_report_uri).to eq(nil)
    end

    it "returns nil if the dsn is not valid" do
      subject.dsn = "foo"
      expect(subject.csp_report_uri).to eq(nil)
    end

    context "when the DSN is present" do
      before do
        subject.release = nil
        subject.environment = nil
        subject.dsn = Sentry::TestHelper::DUMMY_DSN
      end

      it "returns the uri" do
        expect(subject.csp_report_uri).to eq("http://sentry.localdomain/api/42/security/?sentry_key=12345")
      end

      it "adds sentry_release param when there's release information" do
        subject.release = "test-release"
        expect(subject.csp_report_uri).to eq("http://sentry.localdomain/api/42/security/?sentry_key=12345&sentry_release=test-release")
      end

      it "adds sentry_environment param when there's environment information" do
        subject.environment = "test-environment"
        expect(subject.csp_report_uri).to eq("http://sentry.localdomain/api/42/security/?sentry_key=12345&sentry_environment=test-environment")
      end
    end
  end

  describe "#traces_sample_rate" do
    it "returns nil by default" do
      expect(subject.traces_sample_rate).to eq(nil)
    end

    it "accepts Numeric values" do
      subject.traces_sample_rate = 1
      expect(subject.traces_sample_rate).to eq(1)
      subject.traces_sample_rate = 1.0
      expect(subject.traces_sample_rate).to eq(1.0)
    end

    it "accepts nil value" do
      subject.traces_sample_rate = 1
      subject.traces_sample_rate = nil
      expect(subject.traces_sample_rate).to eq(nil)
    end

    it "raises ArgumentError when the value is not Numeric nor nil" do
      expect { Sentry.init { |config| config.traces_sample_rate = "foobar" } }
        .to raise_error(ArgumentError, "must be a Numeric or nil")
    end
  end

  describe "#tracing_enabled?" do
    context "when sending not allowed" do
      before do
        allow(subject).to receive(:sending_allowed?).and_return(false)
      end

      context "when traces_sample_rate > 0" do
        it "returns false" do
          subject.traces_sample_rate = 0.1

          expect(subject.tracing_enabled?).to eq(false)
        end
      end

      context "when traces_sampler is set" do
        it "returns false" do
          subject.traces_sampler = proc { true }

          expect(subject.tracing_enabled?).to eq(false)
        end
      end
    end

    context "when sending allowed" do
      before do
        allow(subject).to receive(:sending_allowed?).and_return(true)
      end

      it "returns false by default" do
        expect(subject.tracing_enabled?).to eq(false)
      end

      context "when traces_sample_rate > 1.0" do
        it "returns false" do
          subject.traces_sample_rate = 1.1

          expect(subject.tracing_enabled?).to eq(false)
        end
      end

      context "when traces_sample_rate == 0.0" do
        it "returns true" do
          subject.traces_sample_rate = 0

          expect(subject.tracing_enabled?).to eq(true)
        end
      end

      context "when traces_sample_rate > 0" do
        it "returns true" do
          subject.traces_sample_rate = 0.1

          expect(subject.tracing_enabled?).to eq(true)
        end
      end

      context "when traces_sampler is set" do
        it "returns true" do
          subject.traces_sampler = proc { true }

          expect(subject.tracing_enabled?).to eq(true)
        end
      end
    end
  end

  describe "#profiles_sample_rate" do
    it "returns nil by default" do
      expect(subject.profiles_sample_rate).to eq(nil)
    end

    it "accepts Numeric values" do
      subject.profiles_sample_rate = 1
      expect(subject.profiles_sample_rate).to eq(1)
      subject.profiles_sample_rate = 1.0
      expect(subject.profiles_sample_rate).to eq(1.0)
    end

    it "accepts nil value" do
      subject.profiles_sample_rate = 1
      subject.profiles_sample_rate = nil
      expect(subject.profiles_sample_rate).to eq(nil)
    end

    it "raises ArgumentError when the value is not Numeric nor nil" do
      expect { Sentry.init { |config| config.profiles_sample_rate = "foobar" } }
        .to raise_error(ArgumentError, "must be a Numeric or nil")
    end
  end

  describe "#profiling_enabled?" do
    it "returns false unless tracing enabled" do
      subject.traces_sample_rate = nil
      expect(subject.profiling_enabled?).to eq(false)
    end

    it "returns false unless sending enabled" do
      subject.traces_sample_rate = 1.0
      subject.profiles_sample_rate = 1.0
      allow(subject).to receive(:sending_allowed?).and_return(false)
      expect(subject.profiling_enabled?).to eq(false)
    end

    context 'when tracing and sending enabled' do
      before { subject.traces_sample_rate = 1.0 }
      before { allow(subject).to receive(:sending_allowed?).and_return(true) }

      it "returns false if nil sample rate" do
        subject.profiles_sample_rate = nil
        expect(subject.profiling_enabled?).to eq(false)
      end

      it "returns false if invalid sample rate" do
        subject.profiles_sample_rate = 5.0
        expect(subject.profiling_enabled?).to eq(false)
      end

      it "returns true if valid sample rate" do
        subject.profiles_sample_rate = 0.5
        expect(subject.profiling_enabled?).to eq(true)
      end
    end
  end

  describe "#transport" do
    it "returns an initialized Transport::Configuration object" do
      transport_config = subject.transport
      expect(transport_config.timeout).to eq(2)
      expect(transport_config.open_timeout).to eq(1)
      expect(transport_config.ssl_verification).to eq(true)
    end
  end

  describe "#cron" do
    it "returns an initialized Cron::Configuration object" do
      expect(subject.cron).to be_a(Sentry::Cron::Configuration)
      expect(subject.cron.default_checkin_margin).to eq(nil)
      expect(subject.cron.default_max_runtime).to eq(nil)
      expect(subject.cron.default_timezone).to eq(nil)
    end
  end

  describe "#spotlight" do
    before do
      ENV.delete('SENTRY_SPOTLIGHT')
    end

    after do
      ENV.delete('SENTRY_SPOTLIGHT')
    end

    it "false by default" do
      expect(subject.spotlight).to eq(false)
    end

    it 'uses `SENTRY_SPOTLIGHT` env variable for truthy' do
      ENV['SENTRY_SPOTLIGHT'] = 'on'

      expect(subject.spotlight).to eq(true)
    end

    it 'uses `SENTRY_SPOTLIGHT` env variable for falsy' do
      ENV['SENTRY_SPOTLIGHT'] = '0'

      expect(subject.spotlight).to eq(false)
    end

    it 'uses `SENTRY_SPOTLIGHT` env variable for custom value' do
      ENV['SENTRY_SPOTLIGHT'] = 'https://my.remote.server:8080/stream'

      expect(subject.spotlight).to eq('https://my.remote.server:8080/stream')
    end
  end

  describe "#debug" do
    before do
      ENV.delete('SENTRY_DEBUG')
    end

    after do
      ENV.delete('SENTRY_DEBUG')
    end

    it "false by default" do
      expect(subject.debug).to eq(false)
    end

    it 'uses `SENTRY_DEBUG` env variable for truthy' do
      ENV['SENTRY_DEBUG'] = 'on'

      expect(subject.debug).to eq(true)
    end

    it 'uses `SENTRY_DEBUG` env variable for falsy' do
      ENV['SENTRY_DEBUG'] = '0'

      expect(subject.debug).to eq(false)
    end

    it 'uses `SENTRY_DEBUG` env variable to turn on random value' do
      ENV['SENTRY_DEBUG'] = 'yabadabadoo'

      expect(subject.debug).to eq(true)
    end
  end

  describe "#sending_allowed?" do
    it "true when spotlight" do
      subject.spotlight = true
      expect(subject.sending_allowed?).to eq(true)
    end

    it "true when sending to dsn allowed" do
      allow(subject).to receive(:sending_to_dsn_allowed?).and_return(true)
      expect(subject.sending_allowed?).to eq(true)
    end

    it "false when no spotlight and sending to dsn not allowed" do
      allow(subject).to receive(:sending_to_dsn_allowed?).and_return(false)
      subject.spotlight = false
      expect(subject.sending_allowed?).to eq(false)
    end
  end

  it 'raises error when setting release to anything other than String' do
    subject.release = "foo"
    expect { subject.release = 42 }.to raise_error(ArgumentError, "expect the argument to be a String or NilClass, got Integer (42)")
  end

  it 'raises error when setting before_send to anything other than callable or nil' do
    subject.before_send = -> { }
    subject.before_send = nil
    expect { subject.before_send = true }.to raise_error(ArgumentError, "before_send must be callable (or nil to disable)")
  end

  it 'raises error when setting before_send_transaction to anything other than callable or nil' do
    subject.before_send_transaction = -> { }
    subject.before_send_transaction = nil
    expect { subject.before_send_transaction = true }.to raise_error(ArgumentError, "before_send_transaction must be callable (or nil to disable)")
  end

  it 'raises error when setting before_send_check_in to anything other than callable or nil' do
    subject.before_send_check_in = -> { }
    subject.before_send_check_in = nil
    expect { subject.before_send_check_in = true }.to raise_error(ArgumentError, "before_send_check_in must be callable (or nil to disable)")
  end

  it 'raises error when setting before_breadcrumb to anything other than callable or nil' do
    subject.before_breadcrumb = -> { }
    subject.before_breadcrumb = nil
    expect { subject.before_breadcrumb = true }.to raise_error(ArgumentError, "before_breadcrumb must be callable (or nil to disable)")
  end

  context 'being initialized with a current environment' do
    before(:each) do
      subject.environment = 'test'
      subject.dsn = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
    end

    it 'should send events if test is whitelisted' do
      subject.enabled_environments = %w[test]
      expect(subject.sending_allowed?).to eq(true)
      expect(subject.errors).to be_empty
    end

    it 'should not send events if test is not whitelisted' do
      subject.enabled_environments = %w[not_test]
      expect(subject.sending_allowed?).to eq(false)
      expect(subject.errors).to eq(["Not configured to send/capture in environment 'test'"])
    end
  end

  context 'being initialized without a current environment' do
    after do
      ENV.delete('SENTRY_CURRENT_ENV')
      ENV.delete('SENTRY_ENVIRONMENT')
      ENV.delete('RAILS_ENV')
      ENV.delete('RACK_ENV')
    end

    it 'defaults to "development"' do
      expect(subject.environment).to eq('development')
    end

    it 'uses `SENTRY_CURRENT_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = 'set-with-sentry-current-env'
      ENV['SENTRY_ENVIRONMENT'] = 'set-with-sentry-environment'
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.environment).to eq('set-with-sentry-current-env')
    end

    it 'uses `SENTRY_ENVIRONMENT` env variable' do
      ENV['SENTRY_ENVIRONMENT'] = 'set-with-sentry-environment'
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.environment).to eq('set-with-sentry-environment')
    end

    it 'uses `RAILS_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = nil
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.environment).to eq('set-with-rails-env')
    end

    it 'uses `RACK_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = nil
      ENV['RAILS_ENV'] = nil
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.environment).to eq('set-with-rack-env')
    end
  end

  describe "config: backtrace_cleanup_callback" do
    it "defaults to nil" do
      expect(subject.backtrace_cleanup_callback).to eq(nil)
    end

    it "takes a proc and store it" do
      subject.backtrace_cleanup_callback = proc { }

      expect(subject.backtrace_cleanup_callback).to be_a(Proc)
    end
  end

  context "with an invalid server" do
    before(:each) do
      subject.dsn = 'dummy://trololo'
    end

    it 'captured_allowed returns false' do
      expect(subject.sending_allowed?).to eq(false)
      expect(subject.errors).to eq(["DSN not set or not valid"])
    end
  end

  context "with the new Sentry 9 DSN format" do
    # Basically the same as before, without a secret
    before(:each) do
      subject.dsn = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"
    end

    it 'captured_allowed is true' do
      expect(subject.sending_allowed?).to eq(true)
    end
  end

  describe "#sample_allowed?" do
    before do
      subject.sample_rate = 0.75
    end

    it 'captured_allowed false when sampled' do
      allow(Random).to receive(:rand).and_return(0.76)
      expect(subject.sample_allowed?).to eq(false)
    end

    it 'captured_allowed true when not sampled' do
      allow(Random).to receive(:rand).and_return(0.74)
      expect(subject.sample_allowed?).to eq(true)
    end
  end

  describe '#exception_class_allowed?' do
    class MyTestException < RuntimeError; end

    context 'with custom excluded_exceptions' do
      before do
        subject.excluded_exceptions = ['MyTestException']
      end

      context 'when the raised exception is a Sentry::Error' do
        let(:incoming_exception) { Sentry::Error.new }
        it 'returns false' do
          expect(subject.exception_class_allowed?(incoming_exception)).to eq false
        end
      end

      context 'when the raised exception is not in excluded_exceptions' do
        let(:incoming_exception) { RuntimeError.new }
        it 'returns true' do
          expect(subject.exception_class_allowed?(incoming_exception)).to eq true
        end
      end

      context 'when the raised exception has a cause that is in excluded_exceptions' do
        let(:incoming_exception) { build_exception_with_cause(MyTestException.new) }
        context 'when inspect_exception_causes_for_exclusion is false' do
          before do
            subject.inspect_exception_causes_for_exclusion = false
          end

          it 'returns true' do
            expect(subject.exception_class_allowed?(incoming_exception)).to eq true
          end
        end

        # Only check causes when they're supported by the ruby version
        context 'when inspect_exception_causes_for_exclusion is true' do
          before do
            subject.inspect_exception_causes_for_exclusion = true
          end

          context 'when the language version supports exception causes' do
            it 'returns false' do
              expect(subject.exception_class_allowed?(incoming_exception)).to eq false
            end
          end
        end
      end

      context 'when the raised exception is in excluded_exceptions' do
        let(:incoming_exception) { MyTestException.new }

        it 'returns false' do
          expect(subject.exception_class_allowed?(incoming_exception)).to eq false
        end
      end
    end
  end

  describe '.add_post_initialization_callback' do
    class SentryConfigurationSample < Sentry::Configuration
      attr_reader :var1, :var2

      add_post_initialization_callback do
        @var1 = 1
      end

      add_post_initialization_callback do
        @var2 = 2
      end
    end

    subject(:configuration) { SentryConfigurationSample }

    it 'calls all hooks and initializes assigned variables' do
      instance = configuration.new

      expect(instance.var1). to eq 1
      expect(instance.var2). to eq 2
    end
  end

  describe '.before' do
    it 'calls a hook before given event' do
      config = Class.new(Sentry::Configuration) do
        attr_reader :info

        before(:initialize) do
          @info = "debug is #{debug.inspect}"
        end
      end.new do |config|
        config.debug = true
      end

      expect(config.info).to eq("debug is nil")
      expect(config.debug).to be(true)
    end
  end

  describe '.after' do
    it 'calls a hook after given event' do
      config = Class.new(Sentry::Configuration) do
        attr_reader :info

        after(:configured) do
          @info = "debug was set to #{debug}"
        end
      end.new do |config|
        config.debug = true
      end

      expect(config.info).to eq("debug was set to true")
    end
  end

  describe "#skip_rake_integration" do
    it "returns false by default" do
      expect(subject.skip_rake_integration).to eq(false)
    end

    it "accepts true" do
      subject.skip_rake_integration = true
      expect(subject.skip_rake_integration).to eq(true)
    end
  end

  describe "#auto_session_tracking" do
    it "returns true by default" do
      expect(subject.auto_session_tracking).to eq(true)
    end

    it "accepts false" do
      subject.auto_session_tracking = false
      expect(subject.auto_session_tracking).to eq(false)
    end
  end

  describe "session_tracking?" do
    before do
      subject.enabled_environments = %w[production]
    end

    context "when auto_session_tracking is true" do
      before do
        subject.auto_session_tracking = true
      end

      it "returns true when in enabled_environments" do
        subject.environment = "production"
        expect(subject.session_tracking?).to eq(true)
      end

      it "returns false when not in enabled_environments" do
        subject.environment = "test"
        expect(subject.session_tracking?).to eq(false)
      end
    end

    context "when auto_session_tracking is false" do
      before do
        subject.auto_session_tracking = false
      end
      it "returns false when in enabled_environments" do
        subject.environment = "production"
        expect(subject.session_tracking?).to eq(false)
      end

      it "returns false when not in enabled_environments" do
        subject.environment = "test"
        expect(subject.session_tracking?).to eq(false)
      end
    end
  end

  describe "#trace_propagation_targets" do
    it "returns match all by default" do
      expect(subject.trace_propagation_targets).to eq([/.*/])
    end

    it "accepts array of strings or regexps" do
      subject.trace_propagation_targets = ["example.com", /foobar.org\/api\/v2/]
      expect(subject.trace_propagation_targets).to eq(["example.com", /foobar.org\/api\/v2/])
    end
  end

  describe "#instrumenter" do
    it "returns :sentry by default" do
      expect(subject.instrumenter).to eq(:sentry)
    end

    it "can be set to :sentry" do
      subject.instrumenter = :sentry
      expect(subject.instrumenter).to eq(:sentry)
    end

    it "can be set to :otel" do
      subject.instrumenter = :otel
      expect(subject.instrumenter).to eq(:otel)
    end

    it "defaults to :sentry if invalid" do
      subject.instrumenter = :foo
      expect(subject.instrumenter).to eq(:sentry)
    end
  end

  describe "#enabled_patches" do
    it "sets default patches" do
      expect(subject.enabled_patches).to eq(%i[redis puma http])
    end

    it "can override" do
      subject.enabled_patches.delete(:puma)
      expect(subject.enabled_patches).to eq(%i[redis http])
    end
  end

  describe "#profiler_class=" do
    it "sets the profiler class to Vernier when it's available", when: :vernier_installed? do
      subject.profiler_class = Sentry::Vernier::Profiler
      expect(subject.profiler_class).to eq(Sentry::Vernier::Profiler)
    end

    it "sets the profiler class to StackProf when Vernier is not available", when: { ruby_version?: [:<, "3.2"] } do
      expect(subject.profiler_class).to eq(Sentry::Profiler)
    end
  end

  describe "#validate" do
    it "logs a warning if StackProf is not installed" do
      allow(Sentry).to receive(:dependency_installed?).with(:StackProf).and_return(false)

      expect {
        Sentry.init do |config|
          config.sdk_logger = Logger.new($stdout)
          config.profiles_sample_rate = 1.0
        end
      }.to output(/Please add the 'stackprof' gem to your Gemfile/).to_stdout
    end

    it "doesn't log a warning when StackProf is not installed and profiles_sample_rate is not set" do
      allow(Sentry).to receive(:dependency_installed?).with(:StackProf).and_return(false)

      expect {
        Sentry.init do |config|
          config.sdk_logger = Logger.new($stdout)
          config.profiles_sample_rate = nil
        end
      }.to_not output(/Please add the 'stackprof' gem to your Gemfile/).to_stdout
    end

    it "logs a warning if Vernier is not installed" do
      allow(Sentry).to receive(:dependency_installed?).with(:Vernier).and_return(false)

      expect {
        Sentry.init do |config|
          config.sdk_logger = Logger.new($stdout)
          config.profiler_class = Sentry::Vernier::Profiler
          config.profiles_sample_rate = 1.0
        end
      }.to output(/Please add the 'vernier' gem to your Gemfile/).to_stdout
    end

    it "doesn't log a warning when Vernier is not installed and profiles_sample_rate is not set" do
      allow(Sentry).to receive(:dependency_installed?).with(:Vernier).and_return(false)

      expect {
        Sentry.init do |config|
          config.sdk_logger = Logger.new($stdout)
          config.profiles_sample_rate = nil
        end
      }.to_not output(/Please add the 'vernier' gem to your Gemfile/).to_stdout
    end
  end

  describe "#logger" do
    it "returns configured sdk_logger and prints deprecation warning" do
      expect {
        expect(subject.logger).to be(subject.sdk_logger)
      }.to output(/`config.logger` is deprecated/).to_stderr
    end
  end

  describe "#logger=" do
    it "sets sdk_logger and prints deprecation warning" do
      expect {
        subject.logger = Logger.new($stdout)
      }.to output(/`config.logger=` is deprecated/).to_stderr
    end
  end

  describe "#trace_ignore_status_codes" do
    it "has default values" do
      expect(subject.trace_ignore_status_codes).to eq([(301..303), (305..399), (401..404)])
    end

    it "can be configured with individual status codes" do
      subject.trace_ignore_status_codes = [404, 500]
      expect(subject.trace_ignore_status_codes).to eq([404, 500])
    end

    it "can be configured with ranges" do
      subject.trace_ignore_status_codes = [(300..399), (500..599)]
      expect(subject.trace_ignore_status_codes).to eq([(300..399), (500..599)])
    end

    it "can be configured with mixed individual codes and ranges" do
      subject.trace_ignore_status_codes = [404, (500..599)]
      expect(subject.trace_ignore_status_codes).to eq([404, (500..599)])
    end

    it "raises ArgumentError when not an Array" do
      expect { subject.trace_ignore_status_codes = 404 }.to raise_error(ArgumentError, /must be an Array/)
      expect { subject.trace_ignore_status_codes = "404" }.to raise_error(ArgumentError, /must be an Array/)
    end

    it "raises ArgumentError for invalid status codes" do
      expect { subject.trace_ignore_status_codes = [99] }.to raise_error(ArgumentError, /must be.* between \(100-599\)/)
      expect { subject.trace_ignore_status_codes = [600] }.to raise_error(ArgumentError, /must be.* between \(100-599\)/)
      expect { subject.trace_ignore_status_codes = ["404"] }.to raise_error(ArgumentError, /must be an Array of integers/)
    end

    it "raises ArgumentError for invalid ranges" do
      expect { subject.trace_ignore_status_codes = [[400]] }.to raise_error(ArgumentError, /must be.* ranges/)
      expect { subject.trace_ignore_status_codes = [[400, 500, 600]] }.to raise_error(ArgumentError, /must be.* ranges/)
      expect { subject.trace_ignore_status_codes = [[500, 400]] }.to raise_error(ArgumentError, /must be.* begin <= end/)
      expect { subject.trace_ignore_status_codes = [[99, 200]] }.to raise_error(ArgumentError, /must be.* between \(100-599\)/)
      expect { subject.trace_ignore_status_codes = [[400, 600]] }.to raise_error(ArgumentError, /must be.* between \(100-599\)/)
    end
  end
end
