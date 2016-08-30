require 'spec_helper'

describe Raven::Logger do
  context 'without a backend logger' do
    before do
      allow(Raven.configuration).to receive(:logger) { nil }
    end

    it 'logs to stdout' do
      expect { subject.fatal 'fatalmsg' }.to output.to_stdout_from_any_process
    end
  end

  # Currently not testing the output here
  context 'with a backend logger' do
    before do
      @logger = double('logger')
      allow(Raven.configuration).to receive(:logger) { @logger }
    end

    it 'should log to the provided logger' do
      expect(@logger).to receive(:fatal).with('sentry')
      subject.fatal 'fatalmsg'
    end

    it 'should log messages from blocks' do
      expect(@logger).to receive(:info).with('sentry')
      subject.info { 'infoblock' }
    end
  end
end
