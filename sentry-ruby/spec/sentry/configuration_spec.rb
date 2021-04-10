require 'spec_helper'

RSpec.describe Sentry::Configuration do
  describe "#breadcrumbs_logger=" do
    it "raises error when given an invalid option" do
      expect { subject.breadcrumbs_logger = :foo }.to raise_error(
        Sentry::Error,
        'Unsupported breadcrumbs logger. Supported loggers: [:sentry_logger, :active_support_logger]'
      )
    end
  end

  describe "#tracing_enabled?" do
    it "returns false by default" do
      expect(subject.tracing_enabled?).to eq(false)
    end

    context "when traces_sample_rate == 0.0" do
      it "returns false" do
        subject.traces_sample_rate = 0

        expect(subject.tracing_enabled?).to eq(false)
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

  it 'should raise when setting before_send to anything other than callable or false' do
    subject.before_send = -> {}
    subject.before_send = false
    expect { subject.before_send = true }.to raise_error(ArgumentError)
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

    it 'defaults to "default"' do
      expect(subject.environment).to eq('default')
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

  context 'being initialized without a release' do
    let(:fake_root) { "/tmp/sentry/" }

    before do
      allow(File).to receive(:directory?).and_return(false)
      allow_any_instance_of(described_class).to receive(:project_root).and_return(fake_root)
    end

    it 'defaults to nil' do
      expect(subject.release).to eq(nil)
    end

    it 'uses `SENTRY_RELEASE` env variable' do
      ENV['SENTRY_RELEASE'] = 'v1'

      expect(subject.release).to eq('v1')

      ENV.delete('SENTRY_CURRENT_ENV')
    end

    context "when git is available" do
      before do
        allow(File).to receive(:directory?).and_return(false)
        allow(File).to receive(:directory?).with(".git").and_return(true)
      end
      it 'gets release from git' do
        allow(Sentry).to receive(:`).with("git rev-parse --short HEAD 2>&1").and_return("COMMIT_SHA")

        expect(subject.release).to eq('COMMIT_SHA')
      end
    end

    context "when Capistrano is available" do
      let(:revision) { "2019010101000" }

      before do
        Dir.mkdir(fake_root) unless Dir.exist?(fake_root)
        File.write(filename, file_content)
      end

      after do
        File.delete(filename)
        Dir.delete(fake_root)
      end

      context "when the REVISION file is present" do
        let(:filename) do
          File.join(fake_root, "REVISION")
        end
        let(:file_content) { revision }

        it "gets release from the REVISION file" do
          expect(subject.release).to eq(revision)
        end
      end

      context "when the revisions.log file is present" do
        let(:filename) do
          File.join(fake_root, "..", "revisions.log")
        end
        let(:file_content) do
          "Branch master (at COMMIT_SHA) deployed as release #{revision} by alice"
        end

        it "gets release from the REVISION file" do
          expect(subject.release).to eq(revision)
        end
      end
    end

    context "when running on heroku" do
      before do
        allow(File).to receive(:directory?).and_return(false)
        allow(File).to receive(:directory?).with("/etc/heroku").and_return(true)
      end

      context "when it's on heroku ci" do
        it "returns nil" do
          begin
            original_ci_val = ENV["CI"]
            ENV["CI"] = "true"

            expect(subject.release).to eq(nil)
          ensure
            ENV["CI"] = original_ci_val
          end
        end
      end

      context "when it's not on heroku ci" do
        around do |example|
          begin
            original_ci_val = ENV["CI"]
            ENV["CI"] = nil

            example.run
          ensure
            ENV["CI"] = original_ci_val
          end
        end

        it "returns nil + logs an warning if HEROKU_SLUG_COMMIT is not set" do
          logger = double("logger")
          expect(::Sentry::Logger).to receive(:new).and_return(logger)
          expect(logger).to receive(:warn).with(Sentry::LOGGER_PROGNAME) { described_class::HEROKU_DYNO_METADATA_MESSAGE }

          expect(described_class.new.release).to eq(nil)
        end

        it "returns HEROKU_SLUG_COMMIT" do
          begin
            ENV["HEROKU_SLUG_COMMIT"] = "REVISION"

            expect(subject.release).to eq("REVISION")
          ensure
            ENV["HEROKU_SLUG_COMMIT"] = nil
          end
        end
      end
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

  context "with a sample rate" do
    before(:each) do
      subject.dsn = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
      subject.sample_rate = 0.75
    end

    it 'captured_allowed false when sampled' do
      allow(Random::DEFAULT).to receive(:rand).and_return(0.76)
      expect(subject.sending_allowed?).to eq(false)
      expect(subject.errors).to eq(["Excluded by random sample"])
    end

    it 'captured_allowed true when not sampled' do
      allow(Random::DEFAULT).to receive(:rand).and_return(0.74)
      expect(subject.sending_allowed?).to eq(true)
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

          if Exception.new.respond_to? :cause
            context 'when the language version supports exception causes' do
              it 'returns false' do
                expect(subject.exception_class_allowed?(incoming_exception)).to eq false
              end
            end
          else
            context 'when the language version does not support exception causes' do
              it 'returns true' do
                expect(subject.exception_class_allowed?(incoming_exception)).to eq true
              end
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
end
