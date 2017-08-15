require 'spec_helper'

describe Raven::Client do
  let(:callback) { double('call' => nil) }
  let(:configuration) do
    config                            = Raven::Configuration.new
    config.dsn                        = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
    config.logger                     = Logger.new(nil)
    config.transport_failure_callback = callback
    config
  end
  let(:client) { Raven::Client.new configuration }

  describe '#failed_send' do
    it 'should mark the client state as error' do
      expect { client.send :failed_send, nil, nil }.to change { client.state.failed? }.from(false).to(true)
    end

    it 'should call transport_failure_callback if it is configured' do
      expect(callback).to receive(:call).with('message' => 'dummy event')
      client.send :failed_send, nil, 'message' => 'dummy event'
    end

    context 'when send event failures are silenced' do
      before { configuration.silence_send_event_failure = true }

      it 'should not log anything to the logger' do
        expect(configuration.logger).not_to receive(:error)
        client.send :failed_send, nil, nil
      end
    end

    context 'when send event failures are not silenced' do
      it 'should log error to the logger' do
        expect(configuration.logger).to receive(:error).exactly(2).times
        client.send :failed_send, nil, nil
      end
    end
  end
end
