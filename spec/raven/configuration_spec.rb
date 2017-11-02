require 'spec_helper'

RSpec.describe Raven::Configuration do
  before do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
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

  it "doesnt accept invalid encodings" do
    expect { subject.encoding = "apple" }.to raise_error(ArgumentError, 'Unsupported encoding')
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

  context 'being initialized with a current environment' do
    before(:each) do
      subject.current_environment = 'test'
      subject.server = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
    end

    it 'should send events if test is whitelisted' do
      subject.environments = %w(test)
      subject.capture_allowed?
      expect(subject.capture_allowed?).to eq(true)
    end

    it 'should not send events if test is not whitelisted' do
      subject.environments = %w(not_test)
      expect(subject.capture_allowed?).to eq(false)
      expect(subject.error_messages).to eq("Not configured to send/capture in environment 'test'")
    end
  end

  context 'being initialized without a current environment' do
    it 'defaults to "default"' do
      expect(subject.current_environment).to eq('default')
    end

    it 'uses `SENTRY_CURRENT_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = 'set-with-sentry-current-env'
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-sentry-current-env')

      ENV.delete('SENTRY_CURRENT_ENV')
      ENV.delete('RAILS_ENV')
      ENV.delete('RACK_ENV')
    end

    it 'uses `RAILS_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = nil
      ENV['RAILS_ENV'] = 'set-with-rails-env'
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-rails-env')

      ENV.delete('SENTRY_CURRENT_ENV')
      ENV.delete('RAILS_ENV')
      ENV.delete('RACK_ENV')
    end

    it 'uses `RACK_ENV` env variable' do
      ENV['SENTRY_CURRENT_ENV'] = nil
      ENV['RAILS_ENV'] = nil
      ENV['RACK_ENV'] = 'set-with-rack-env'

      expect(subject.current_environment).to eq('set-with-rack-env')

      ENV.delete('SENTRY_CURRENT_ENV')
      ENV.delete('RAILS_ENV')
      ENV.delete('RACK_ENV')
    end
  end

  context 'with a should_capture callback configured' do
    before(:each) do
      subject.should_capture = ->(exc_or_msg) { exc_or_msg != "dont send me" }
      subject.server = 'http://12345:67890@sentry.localdomain:3000/sentry/42'
    end

    it 'should not send events if should_capture returns false' do
      expect(subject.capture_allowed?("dont send me")).to eq(false)
      expect(subject.error_messages).to eq("should_capture returned false")
      expect(subject.capture_allowed?("send me")).to eq(true)
    end
  end

  context "with an invalid server" do
    before(:each) do
      subject.server = 'dummy://trololo'
    end

    it 'captured_allowed returns false' do
      expect(subject.capture_allowed?).to eq(false)
      expect(subject.error_messages).to eq("No path specified, no public_key specified, no secret_key specified, no project_id specified")
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
      expect(subject.error_messages).to eq("Excluded by random sample")
    end

    it 'captured_allowed true when not sampled' do
      allow(Random::DEFAULT).to receive(:rand).and_return(0.74)
      expect(subject.capture_allowed?).to eq(true)
    end
  end
end
