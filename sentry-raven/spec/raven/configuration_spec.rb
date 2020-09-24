require 'spec_helper'

RSpec.describe Raven::Configuration do
  before do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
    ENV.delete('SENTRY_ENVIRONMENT')
    ENV.delete('SENTRY_RELEASE')
    ENV.delete('RAILS_ENV')
    ENV.delete('RACK_ENV')
  end

  it "should set some attributes when server is set" do
    subject.server = "http://12345:67890@sentry.localdomain:3000/sentry/42"

    expect(subject.project_id).to eq("42")
    expect(subject.public_key).to eq("12345")
    expect(subject.secret_key).to eq("67890")

    expect(subject.scheme).to     eq("http")
    expect(subject.host).to       eq("sentry.localdomain")
    expect(subject.port).to       eq(3000)
    expect(subject.path).to       eq("/sentry")

    expect(subject.server).to     eq("http://sentry.localdomain:3000/sentry")
  end

  describe "#breadcrumbs_logger=" do
    it "raises error when given an invalid option" do
      expect { subject.breadcrumbs_logger = :foo }.to raise_error(
        Raven::Error,
        'Unsupported breadcrumbs logger. Supported loggers: [:sentry_logger, :active_support_logger]'
      )
    end
  end

  it "doesnt accept invalid encodings" do
    expect { subject.encoding = "apple" }.to raise_error(Raven::Error, 'Unsupported encoding')
  end

  it "has hashlike attribute accessors" do
    expect(subject.encoding).to   eq("gzip")
    expect(subject[:encoding]).to eq("gzip")
  end

  context 'configuring for async' do
    it 'should be configurable to send events async' do
      subject.async = ->(_e) { :ok }
      expect(subject.async.call('event')).to eq(:ok)
    end

    it 'should raise when setting async to anything other than callable or false' do
      subject.transport_failure_callback = -> {}
      subject.transport_failure_callback = false
      expect { subject.async = true }.to raise_error(ArgumentError)
    end
  end

  it 'should raise when setting transport_failure_callback to anything other than callable or false' do
    subject.transport_failure_callback = -> {}
    subject.transport_failure_callback = false
    expect { subject.transport_failure_callback = true }.to raise_error(ArgumentError)
  end

  it 'should raise when setting should_capture to anything other than callable or false' do
    subject.should_capture = -> {}
    subject.should_capture = false
    expect { subject.should_capture = true }.to raise_error(ArgumentError)
  end

  it 'should raise when setting before_send to anything other than callable or false' do
    subject.before_send = -> {}
    subject.before_send = false
    expect { subject.before_send = true }.to raise_error(ArgumentError)
  end

  context 'being initialized with a current environment' do
    before(:each) do
      subject.current_environment = 'test'
      subject.server = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
    end

    it 'should send events if test is whitelisted' do
      subject.environments = %w(test)
      subject.capture_allowed?
      puts subject.errors
      expect(subject.capture_allowed?).to eq(true)
    end

    it 'should not send events if test is not whitelisted' do
      subject.environments = %w(not_test)
      expect(subject.capture_allowed?).to eq(false)
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
      expect(subject.current_environment).to eq('default')
    end

    it 'uses `SENTRY_CURRENT_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = 'set-with-sentry-current-env'
      ENV['SENTRY_ENVIRONMENT'] = 'set-with-sentry-environment'
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-sentry-current-env')
    end

    it 'uses `SENTRY_ENVIRONMENT` env variable' do
      ENV['SENTRY_ENVIRONMENT'] = 'set-with-sentry-environment'
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-sentry-environment')
    end

    it 'uses `RAILS_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = nil
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-rails-env')
    end

    it 'uses `RACK_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = nil
      ENV['RAILS_ENV'] = nil
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-rack-env')
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
        allow(Raven).to receive(:`).with("git rev-parse --short HEAD 2>&1").and_return("COMMIT_SHA")

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
          expect(::Raven::Logger).to receive(:new).and_return(logger)
          expect(logger).to receive(:warn).with(described_class::HEROKU_DYNO_METADATA_MESSAGE)

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

  context 'with a should_capture callback configured' do
    before(:each) do
      subject.should_capture = ->(exc_or_msg) { exc_or_msg != "dont send me" }
      subject.server = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
    end

    it 'should not send events if should_capture returns false' do
      expect(subject.capture_allowed?("dont send me")).to eq(false)
      expect(subject.errors).to eq(["should_capture returned false"])
      expect(subject.capture_allowed?("send me")).to eq(true)
    end
  end

  context "with an invalid server" do
    before(:each) do
      subject.server = 'dummy://trololo'
    end

    it 'captured_allowed returns false' do
      expect(subject.capture_allowed?).to eq(false)
      expect(subject.errors).to eq(["No public_key specified", "No project_id specified"])
    end
  end

  context "with the new Sentry 9 DSN format" do
    # Basically the same as before, without a secret
    before(:each) do
      subject.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"
    end

    it 'captured_allowed is true' do
      expect(subject.capture_allowed?).to eq(true)
    end

    it "sets the DSN in the way we expect" do
      expect(subject.dsn).to eq("https://66260460f09b5940498e24bb7ce093a0@sentry.io/42")
      expect(subject.server).to eq("https://sentry.io")
      expect(subject.project_id).to eq("42")
      expect(subject.public_key).to eq("66260460f09b5940498e24bb7ce093a0")
      expect(subject.secret_key).to be_nil
    end
  end

  context "with a sample rate" do
    before(:each) do
      subject.server = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
      subject.sample_rate = 0.75
    end

    it 'captured_allowed false when sampled' do
      allow(Random::DEFAULT).to receive(:rand).and_return(0.76)
      expect(subject.capture_allowed?).to eq(false)
      expect(subject.errors).to eq(["Excluded by random sample"])
    end

    it 'captured_allowed true when not sampled' do
      allow(Random::DEFAULT).to receive(:rand).and_return(0.74)
      expect(subject.capture_allowed?).to eq(true)
    end
  end

  describe '#exception_class_allowed?' do
    class MyTestException < RuntimeError; end

    context 'with custom excluded_exceptions' do
      before do
        subject.excluded_exceptions = ['MyTestException']
      end

      context 'when the raised exception is a Raven::Error' do
        let(:incoming_exception) { Raven::Error.new }
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
end
