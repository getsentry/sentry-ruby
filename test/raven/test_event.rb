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

    assert_equal Raven.configuration, @event.configuration
    assert_equal Raven.breadcrumbs, @event.breadcrumbs
    assert_equal Raven.context, @event.context

    assert_equal Raven.configuration.server_name, @event.server_name
    assert_equal Raven.configuration.release, @event.release
    assert_equal Raven.configuration.current_environment, @event.environment
  end

  it "can be created from an exception" do
  end

  it "can use an exceptions raven_context during creation" do
    # use both methods
    # check merge priority
  end

  it "can be created from a message (string)" do
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

  it "rejects bad interface names" do
    @event = Raven::Event.new

    assert_raises(Raven::Error) { @event.interface(:nonexistent) }
  end

  it "adds interfaces" do
    @event = Raven::Event.new

    @event.interface(:message) { |i| i.message = "Hi!" }

    assert_equal "Hi!", @event[:message].message
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
