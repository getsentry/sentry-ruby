require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven do
  let(:event) { double("event") }
  let(:options) { double("options") }

  before do
    Raven.stub(:send)
    Raven::Event.stub(:capture_message) { event }
    Raven::Event.stub(:capture_exception) { event }
  end

  describe '.capture_message' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_message' do
      Raven::Event.should_receive(:capture_message).with(message, options)
      Raven.should_receive(:send).with(event)

      Raven.capture_message(message, options)
    end

    it 'yields the event to a passed block' do
      expect { |b| Raven.capture_message(message, options, &b) }.to yield_with_args(event)
    end
  end

  describe '.capture_exception' do
    let(:exception) { build_exception }

    it 'sends the result of Event.capture_exception' do
      Raven::Event.should_receive(:capture_exception).with(exception, options)
      Raven.should_receive(:send).with(event)

      Raven.capture_exception(exception, options)
    end

    it 'yields the event to a passed block' do
      expect { |b| Raven.capture_exception(exception, options, &b) }.to yield_with_args(event)
    end
  end
end
