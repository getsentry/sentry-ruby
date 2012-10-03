require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven do
  before do
    @send = double("send")
    @event = double("event")
    Raven.stub(:send) { @send }
    Raven::Event.stub(:capture_message) { @event }
    Raven::Event.stub(:capture_exception) { @event }
  end

  it 'captureMessage should send result of Event.capture_message' do
    message = "Test message"
    Raven::Event.should_receive(:capture_message).with(message)
    Raven.should_receive(:send).with(@event)

    Raven.captureMessage(message)
  end

  it 'captureException should send result of Event.capture_exception' do
    exception = build_exception()

    Raven::Event.should_receive(:capture_exception).with(exception)
    Raven.should_receive(:send).with(@event)

    Raven.captureException(exception)
  end
end
