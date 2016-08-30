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

  context 'with a backend logger' do
    before do
      @logger = double('logger')
      allow(Raven.configuration).to receive(:logger) { @logger }
    end

    it 'should log fatal messages' do
      expect(@logger).to receive(:add).with(Logger::FATAL, '** [Raven] fatalmsg', 'sentry')
      subject.fatal 'fatalmsg'
    end

    it 'should log error messages' do
      expect(@logger).to receive(:add).with(Logger::ERROR, '** [Raven] errormsg', 'sentry')
      subject.error 'errormsg'
    end

    it 'should log warning messages' do
      expect(@logger).to receive(:add).with(Logger::WARN, '** [Raven] warnmsg', 'sentry')
      subject.warn 'warnmsg'
    end

    it 'should log info messages' do
      expect(@logger).to receive(:add).with(Logger::INFO, '** [Raven] infomsg', 'sentry')
      subject.info 'infomsg'
    end

    it 'should log debug messages' do
      expect(@logger).to receive(:add).with(Logger::DEBUG, '** [Raven] debugmsg', 'sentry')
      subject.debug 'debugmsg'
    end

    it 'should log messages from blocks' do
      expect(@logger).to receive(:add).with(Logger::INFO, '** [Raven] infoblock', 'sentry')
      subject.info { 'infoblock' }
    end
  end
end
