require 'spec_helper'

RSpec.describe Sentry::Configuration do
  describe "#capture_exception_frame_locals" do
    it "passes/received the value to #include_local_variables" do
      subject.capture_exception_frame_locals = true
      expect(subject.include_local_variables).to eq(true)
      expect(subject.capture_exception_frame_locals).to eq(true)

      subject.capture_exception_frame_locals = false
      expect(subject.include_local_variables).to eq(false)
      expect(subject.capture_exception_frame_locals).to eq(false)
    end

    it "prints deprecation message when being assigned" do
      string_io = StringIO.new
      subject.logger = Logger.new(string_io)

      subject.capture_exception_frame_locals = true

      expect(string_io.string).to include(
        "WARN -- sentry: `capture_exception_frame_locals` is now deprecated in favor of `include_local_variables`."
      )
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
      expect { subject.traces_sample_rate = "foobar" }.to raise_error(ArgumentError)
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

      context "when enable_tracing is set" do
        it "returns false" do
          subject.enable_tracing = true

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

      context "when enable_tracing is true" do
        it "returns true" do
          subject.enable_tracing = true

          expect(subject.tracing_enabled?).to eq(true)
        end
      end

      context "when enable_tracing is false" do
        it "returns false" do
          subject.enable_tracing = false

          expect(subject.tracing_enabled?).to eq(false)
        end

        it "returns false even with explicit traces_sample_rate" do
          subject.traces_sample_rate = 1.0
          subject.enable_tracing = false

          expect(subject.tracing_enabled?).to eq(false)
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
      expect { subject.profiles_sample_rate = "foobar" }.to raise_error(ArgumentError)
    end
  end

  describe "#profiling_enabled?" do
    it "returns false unless tracing enabled" do
      subject.enable_tracing = false
      expect(subject.profiling_enabled?).to eq(false)
    end

    it "returns false unless sending enabled" do
      subject.enable_tracing = true
      subject.profiles_sample_rate = 1.0
      allow(subject).to receive(:sending_allowed?).and_return(false)
      expect(subject.profiling_enabled?).to eq(false)
    end

    context 'when tracing and sending enabled' do
      before { subject.enable_tracing = true }
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

  describe "#enable_tracing=" do
    it "sets traces_sample_rate to 1.0 automatically" do
      subject.enable_tracing = true
      expect(subject.traces_sample_rate).to eq(1.0)
    end

    it "doesn't override existing traces_sample_rate" do
      subject.traces_sample_rate = 0.5
      subject.enable_tracing = true
      expect(subject.traces_sample_rate).to eq(0.5)
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

  context 'configuring for async' do
    it 'should be configurable to send events async' do
      subject.async = ->(_e) { :ok }
      expect(subject.async.call('event')).to eq(:ok)
    end
  end

  it 'raises error when setting release to anything other than String' do
    subject.release = "foo"
    expect { subject.release = 42 }.to raise_error(ArgumentError, "expect the argument to be a String or NilClass, got Integer (42)")
  end

  it 'raises error when setting async to anything other than callable or nil' do
    subject.async = -> {}
    subject.async = nil
    expect { subject.async = true }.to raise_error(ArgumentError, "async must be callable (or nil to disable)")
  end

  it 'raises error when setting before_send to anything other than callable or nil' do
    subject.before_send = -> {}
    subject.before_send = nil
    expect { subject.before_send = true }.to raise_error(ArgumentError, "before_send must be callable (or nil to disable)")
  end

  it 'raises error when setting before_send_transaction to anything other than callable or nil' do
    subject.before_send_transaction = -> {}
    subject.before_send_transaction = nil
    expect { subject.before_send_transaction = true }.to raise_error(ArgumentError, "before_send_transaction must be callable (or nil to disable)")
  end

  it 'raises error when setting before_breadcrumb to anything other than callable or nil' do
    subject.before_breadcrumb = -> {}
    subject.before_breadcrumb = nil
    expect { subject.before_breadcrumb = true }.to raise_error(ArgumentError, "before_breadcrumb must be callable (or nil to disable)")
  end

  context 'being initialized with a current environment' do
    before(:each) do
      subject.environment = 'test'
      subject.dsn = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
    end

    it 'should send events if test is whitelisted' do
      subject.enabled_environments = %w(test)
      subject.sending_allowed?
      puts subject.errors
      expect(subject.sending_allowed?).to eq(true)
    end

    it 'should not send events if test is not whitelisted' do
      subject.enabled_environments = %w(not_test)
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
      subject.backtrace_cleanup_callback = proc {}

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
end
