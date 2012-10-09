require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven::Event do
  before do
    @send = double("send")
    @event = double("event")
  end

  it 'capture_message should build event' do
    message = "Test message"
    evt = Raven::Event.capture_message(message)
    evt.message.should eq(message)
    evt.level.should eq(40)
  end

  it 'capture_exception should build event' do
    exception = build_exception()
    evt = Raven::Event.capture_exception(exception)
    evt.message.should eq("ZeroDivisionError: divided by 0")
    evt.level.should eq(40)
    evt.culprit.should eq("spec_helper.rb in /")
  end

end
