require 'spec_helper'

describe Raven::Configuration do
  before do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
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

  context 'being initialized with a current environment' do
    before(:each) do
      subject.current_environment = 'test'
      subject.server = 'http://sentry.localdomain/sentry'
    end

    it 'should send events if test is whitelisted' do
      subject.environments = %w(test)
      expect(subject.capture_allowed?).to eq(true)
    end

    it 'should not send events if test is not whitelisted' do
      subject.environments = %w(not_test)
      expect(subject.capture_allowed?).to eq(false)
    end
  end

  context 'with a should_capture callback configured' do
    before(:each) do
      subject.should_capture = ->(exc_or_msg) { exc_or_msg != "dont send me" }
      subject.server = 'http://sentry.localdomain/sentry'
    end

    it 'should not send events if should_capture returns false' do
      expect(subject.capture_allowed?("dont send me")).to eq(false)
      expect(subject.capture_allowed?("send me")).to eq(true)
    end
  end

  it "should verify server configuration, looking for missing keys" do
    expect { subject.verify! }.to raise_error(Raven::Error, "No server specified")

    subject.server, subject.public_key, subject.secret_key, subject.project_id = "", "", "", ""

    subject.verify!
  end
end
