require 'spec_helper'

describe Raven::Configuration do
  before do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('RAILS_ENV')
    ENV.delete('RACK_ENV')
  end

  shared_examples 'a complete configuration' do
    it 'should have a server' do
      expect(subject[:server]).to eq('http://sentry.localdomain/sentry')
    end

    it 'should have a scheme' do
      expect(subject[:scheme]).to eq('http')
    end

    it 'should have a public key' do
      expect(subject[:public_key]).to eq('12345')
    end

    it 'should have a secret key' do
      expect(subject[:secret_key]).to eq('67890')
    end

    it 'should have a host' do
      expect(subject[:host]).to eq('sentry.localdomain')
    end

    it 'should have a port' do
      expect(subject[:port]).to eq(80)
    end

    it 'should have a path' do
      expect(subject[:path]).to eq('/sentry')
    end

    it 'should have a project ID' do
      expect(subject[:project_id]).to eq('42')
    end

    it 'should not be async' do
      expect(subject[:async]).to eq(false)
      expect(subject[:async?]).to eq(false)
    end

    it 'should catch_debugged_exceptions' do
      expect(subject[:catch_debugged_exceptions]).to eq(true)
    end

    it 'should have no sanitize fields' do
      expect(subject[:sanitize_fields]).to eq([])
    end
  end

  context 'being initialized without server configuration' do
    before do
      subject.environments = %w[ test ]
    end

    it 'should not send events' do
      expect(subject[:server]).to eq(nil)
      expect(subject.send_in_current_environment?).to eq(false)
    end
  end

  context 'being initialized with a server string' do
    before do
      subject.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
    it_should_behave_like 'a complete configuration'
  end

  context 'being initialized with a DSN string' do
    before do
      subject.dsn = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
    it_should_behave_like 'a complete configuration'
  end

  context 'being initialized with options' do
    before do
      subject.server = 'http://sentry.localdomain/sentry'
      subject.public_key = '12345'
      subject.secret_key = '67890'
      subject.project_id = '42'
    end
    it_should_behave_like 'a complete configuration'
  end

  context 'being initialized with an environment variable' do
    subject do
      ENV['SENTRY_DSN'] = 'http://12345:67890@sentry.localdomain/sentry/42'
      Raven::Configuration.new
    end
    it_should_behave_like 'a complete configuration'
  end

  context 'configuring for async' do
    it 'should be configurable to send events async' do
      subject.async = lambda { |_e| :ok }
      expect(subject.async.respond_to?(:call)).to eq(true)
      expect(subject.async.call('event')).to eq(:ok)
    end

    it 'should raise when setting async to anything other than callable or false' do
      expect { subject.async = Proc.new {} }.to_not raise_error
      expect { subject.async = lambda {} }.to_not raise_error
      expect { subject.async = false }.to_not raise_error
      expect { subject.async = true }.to raise_error(ArgumentError)
    end
  end

  context 'being initialized with a current environment' do
    before(:each) do
      subject.current_environment = 'test'
      subject.server = 'http://sentry.localdomain/sentry'
    end

    it 'should send events if test is whitelisted' do
      subject.environments = %w[ test ]
      expect(subject.send_in_current_environment?).to eq(true)
    end

    it 'should not send events if test is not whitelisted' do
      subject.environments = %w[ not_test ]
      expect(subject.send_in_current_environment?).to eq(false)
    end
  end

  context 'configuration for sanitize fields' do
    it 'should union default sanitize fields with user-defined sanitize fields' do
      fields = Raven::Processor::SanitizeData::DEFAULT_FIELDS | %w(test monkeybutt)

      subject.sanitize_fields = fields
      client = Raven::Client.new(subject)
      processor = Raven::Processor::SanitizeData.new(client)

      expect(processor.send(:fields_re)).to eq(/(#{fields.join('|')})/i)
    end
  end

end
