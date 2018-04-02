require "test_helper"

class TestEvent < Raven::Test
  it "has some defaults" do
    time = Time.now
    Time.stub(:now, time) do
      @event = Raven::Event.new
    end

    assert_equal :error, @event.level
    assert_equal :ruby,  @event.logger
    assert_equal :ruby,  @event.platform
    assert_equal Raven::Event::SDK, @event.sdk
    assert_match(/[0-9a-fA-F]+/, @event.event_id)
    assert_equal time.utc.strftime(Raven::Event::TIME_FORMAT), @event.timestamp

    assert_kind_of Raven::Configuration, @event.configuration
    assert_kind_of Raven::BreadcrumbBuffer, @event.breadcrumbs
  end

  it "coerces messages" do
    @event = Raven::Event.new(:message => ["This is a parameterized message: %s", "and a parameter"])

    assert_equal "This is a parameterized message: and a parameter", @event.message
  end

  it "cuts messages to 8kb" do
    message = "aa" * Raven::Event::MAX_MESSAGE_SIZE_IN_BYTES # Double max size
    @event = Raven::Event.new(:message => message)

    assert_equal Raven::Event::MAX_MESSAGE_SIZE_IN_BYTES, @event.message.length
  end

  it "coerces timestamps" do
    time = Time.now
    @event = Raven::Event.new(:timestamp => time)

    assert_equal time.utc.strftime(Raven::Event::TIME_FORMAT), @event.timestamp
  end

  it "coerces time_spent" do
    time = 0.001
    @event = Raven::Event.new(:time_spent => time)

    assert_equal 1, @event.time_spent
  end

  it "coerces the loglevel" do
    @event = Raven::Event.new(:level => "WARN")

    assert_equal :warning, @event.level
  end

  it "can be created from an exception" do
    evt = Raven::Event.from_exception(Exception.new("This is a message"))

    assert_equal "Exception: This is a message", evt.message
  end

  it "can set any number of options on the created exception" do
    evt = Raven::Event.from_exception(
      Exception.new("This is a message"),
      :logger => "Mylogger",
      :checksum => "AAAAA",
      :release => "1.0"
    )

    assert_equal "Mylogger", evt.logger
    assert_equal "AAAAA", evt.checksum
    assert_equal "1.0", evt.release
  end

  it "rejects options which do not exist on Event" do
    assert_raises(NoMethodError) do
      Raven::Event.from_exception(
        Exception.new("This is a message"),
        :foo => "bar"
      )
    end
  end

  class ExceptionWithContext < StandardError
    def raven_context
      { :extra => {
        'context_event_key' => 'context_value',
        'context_key' => 'context_value'
      } }
    end
  end

  it "can use an exceptions raven_context during creation" do
    evt = Raven::Event.from_exception(
      ExceptionWithContext.new,
      :extra => {
        'context_event_key' => 'event_value',
        'event_key' => 'event_value'
      }
    )

    assert_equal 'event_value', evt.extra['context_event_key']
    assert_equal 'context_value', evt.extra['context_key']
    assert_equal 'event_value', evt.extra['event_key']
  end

  it "adds an exception interface" do
    evt = Raven::Event.from_exception(Exception.new("This is a message"))

    assert_kind_of Raven::ExceptionInterface, evt.exception
  end

  it "can be created from a message (string)" do
    evt = Raven::Event.from_message("This is a message", :logger => "foo")

    assert_equal "This is a message", evt.message
    assert_equal "foo", evt.logger
  end

  it "can be created from a message with an optional backtrace" do
    backtrace = [
      OpenStruct.new(:lineno => 22, :to_s => "/path/to/some/file:22:in `function_name'", :path => "/path/to/some/file"),
      OpenStruct.new(:lineno => 1412, :to_s => "/some/other/path:1412:in `other_function'", :path => "/some/other/path")
    ]
    evt = Raven::Event.from_message("This is a test", :backtrace => backtrace)
    assert_kind_of Raven::StacktraceInterface, evt.stacktrace

    frames = evt.stacktrace.to_hash[:frames]
    assert_equal 2, frames.length
    assert_equal 1412, frames[0][:lineno]
    assert_equal 'other_function', frames[0][:function]
    assert_equal '/some/other/path', frames[0][:filename]

    assert_equal 22, frames[1][:lineno]
    assert_equal 'function_name', frames[1][:function]
    assert_equal '/path/to/some/file', frames[1][:filename]
  end

  it "formats timestamps" do
    @event = Raven::Event.new
    time = Time.now

    @event.timestamp = time
    assert_equal time.utc.strftime(Raven::Event::TIME_FORMAT), @event.timestamp
  end

  it "formats time_spent" do
    @event = Raven::Event.new

    @event.time_spent = 1.0

    assert_equal 1000, @event.time_spent
  end

  it "formats levels according to the sentry spec" do
    @event = Raven::Event.new

    @event.level = :warn

    assert_equal :warning, @event.level
  end

  it "converts to a hash" do
    @event = Raven::Event.new(:message => "Hi!")

    hash = @event.to_hash

    assert_instance_of Hash, hash
    assert_equal :ruby, hash[:logger]
    assert_equal "Hi!", hash[:logentry][:message]
  end

  it "can convert to a guaranteed json compatible hash" do
    @event = Raven::Event.new(:message => "Hi!", :extra => { :not_json => StringIO.new("Foo") })

    json = @event.to_json_compatible

    assert_equal "Hi!", json["logentry"]["message"]
    assert_match "#<StringIO:", json["extra"]["not_json"]
  end
end
