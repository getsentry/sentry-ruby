require 'spec_helper'

describe Raven::Logger do
  context 'without a backend logger' do
    before do
      allow(Raven.configuration).to receive(:logger) { nil }
    end

    it 'should not error' do
      subject.fatal 'fatalmsg'
      subject.error 'errormsg'
      subject.warn 'warnmsg'
      subject.info 'infomsg'
      subject.debug 'debugmsg'
    end
  end

  context 'with a backend logger' do
    before do
      @logger = double('logger')
      allow(Raven.configuration).to receive(:logger) { @logger }
    end

    it 'should log fatal messages' do
      expect(@logger).to receive(:fatal).with('** [Raven] fatalmsg')
      subject.fatal 'fatalmsg'
    end

    it 'should log error messages' do
      expect(@logger).to receive(:error).with('** [Raven] errormsg')
      subject.error 'errormsg'
    end

    it 'should log warning messages' do
      expect(@logger).to receive(:warn).with('** [Raven] warnmsg')
      subject.warn 'warnmsg'
    end

    it 'should log info messages' do
      expect(@logger).to receive(:info).with('** [Raven] infomsg')
      subject.info 'infomsg'
    end

    it 'should log debug messages' do
      expect(@logger).to receive(:debug).with('** [Raven] debugmsg')
      subject.debug 'debugmsg'
    end

    it 'should log messages from blocks' do
      expect(@logger).to receive(:info).with('** [Raven] infoblock')
      subject.info { 'infoblock' }
    end
  end
end
