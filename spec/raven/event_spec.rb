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
end
