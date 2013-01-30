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

  it 'captureMessage should send result of Event#capture_message' do
    message = "Test message"
    options = {}

    Raven::Event.should_receive(:capture_message).with(message, options)
    Raven.should_receive(:send).with(@event)

    Raven.captureMessage(message, options)
  end

  it 'captureException should send result of Event#capture_exception' do
    exception = build_exception()
    options   = {}

    Raven::Event.should_receive(:capture_exception).with(exception, options)
    Raven.should_receive(:send).with(@event)

    Raven.captureException(exception)
  end

  describe '#context' do
    before do
      Thread.current[:sentry_context] = nil
    end
 
    it 'should bind context to Thread' do
      Raven.context({ :foo => :bar })

      Thread.current[:sentry_context].should == { :foo => :bar }
    end
    
    describe '#clear!' do
      it 'should empty the contest' do
        Thread.current[:sentry_context] = { :foo => :bar }
        Raven.context.clear!

        Thread.current[:sentry_context].should eq(nil)
      end
    end

  end

end
