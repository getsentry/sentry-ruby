require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven::Rack do
  before do
    @send = double("send")
    @event = double("event")
    Raven.stub(:send) { @send }
    Raven::Event.stub(:capture_rack_exception) { @event }
  end

  it 'should capture exceptions' do
    exception = build_exception()
    env = { 'key' => 'value' }

    app = lambda do |e|
      raise exception
    end

    stack = Raven::Rack.new(app)

    Raven::Event.should_receive(:capture_rack_exception).with(exception, env)
    Raven.should_receive(:send).with(@event)
    
    lambda {stack.call(env)}.should raise_error(exception)
  end
end
