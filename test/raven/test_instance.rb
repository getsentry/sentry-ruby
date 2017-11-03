require 'test_helper'

class TestInstance < Raven::Test
  it "has a context and configuration by default" do
    @instance = Raven::Instance.new

    assert_instance_of Raven::Configuration, @instance.configuration
    assert_instance_of Raven::Context, @instance.context
    assert_equal Raven::Context.current, @instance.context
  end

  it "can be initialized with a Context which is not the default" do
    ctx = Raven::Context.new
    @instance = Raven::Instance.new(ctx)

    refute_equal Raven::Context.current, @instance.context
    assert_equal ctx, @instance.context
  end

  it "can initialize new context only by passing true as first arg" do
    @instance = Raven::Instance.new(true)

    refute_equal Raven::Context.current, @instance.context
  end

  it "has a logger" do
    @instance = Raven::Instance.new

    assert_equal @instance.configuration.logger, @instance.logger
  end

  it "has a client" do
    @instance = Raven::Instance.new

    assert_instance_of Raven::Client, @instance.client
  end

  it "does not report status if config does not allow" do
    @instance = Raven::Instance.new
    @instance.configuration.silence_ready = true

    refute @instance.report_status
  end

  it "reports status" do
    @instance = Raven::Instance.new
    strio = StringIO.new
    @instance.configuration.logger = Logger.new(strio)
    @instance.report_status

    assert_match(/configured not to capture errors: DSN not set/, strio.string)

    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"

    @instance.report_status

    assert_match(/ready to catch errors/, strio.string)
  end

  it "configures with a block" do
    @instance = Raven::Instance.new
    strio = StringIO.new
    @instance.configuration.logger = Logger.new(strio)

    inst = @instance.configure { |c| c.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42" }

    assert_match(/ready to catch errors/, strio.string)

    assert_equal inst, @instance
  end

  it "delegates send_event to client" do
    @instance = Raven::Instance.new
    client = Minitest::Mock.new
    client.expect :send_event, true, [Hash]
    @instance.instance_variable_set(:@client, client)

    @instance.send_event(:foo => :bar)

    client.verify
  end

  it "captures in a block" do
    @instance = Raven::Instance.new
    @instance.configuration.logger = Logger.new(nil)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"

    assert_raises(ZeroDivisionError) { @instance.capture { 1 / 0 } }

    assert_equal 1, @instance.client.transport.events.size
  end

  it "doesnt capture if it is not allowed" do
    @instance = Raven::Instance.new
    strio = StringIO.new
    @instance.configuration.logger = Logger.new(strio)

    refute @instance.capture_type("Message")
    assert_match(/excluded from capture: DSN not set/, strio.string)
  end

  it "captures messages" do
    @instance = Raven::Instance.new
    @instance.configuration.logger = Logger.new(nil)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"

    evt = @instance.capture_type("Message")
    assert_instance_of Raven::Event, evt
    assert_equal 1, @instance.client.transport.events.size
  end

  it "captures exceptions" do
    @instance = Raven::Instance.new
    @instance.configuration.logger = Logger.new(nil)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"
    exc = ZeroDivisionError.new

    evt = @instance.capture_type(exc)
    assert_instance_of Raven::Event, evt
    assert_equal 1, @instance.client.transport.events.size
  end

  it "sets the last event id for the thread" do
    @instance = Raven::Instance.new
    @instance.configuration.logger = Logger.new(nil)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"

    evt = @instance.capture_type("Message")

    assert_equal evt.event_id, @instance.last_event_id
  end

  it "can capture with access to the event via block" do
    @instance = Raven::Instance.new
    @instance.configuration.logger = Logger.new(nil)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"

    evt = @instance.capture_type("Message") { |e| e.message = "my message" }

    assert_equal "my message", evt.message
  end

  it "capture_type passes to the async callable" do
    @instance = Raven::Instance.new
    @instance.configuration.logger = Logger.new(nil)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"
    @instance.configuration.async = proc { |evt| @evt = evt }

    evt = @instance.capture_type("Message")

    assert_equal evt.to_json_compatible, @evt
  end

  it "sends anyway if async raises an exception" do
    @instance = Raven::Instance.new
    strio = StringIO.new
    @instance.configuration.logger = Logger.new(strio)
    @instance.configuration.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"
    @instance.configuration.async = proc { |_evt| raise "Boom!" }

    assert @instance.capture_type("Message")
    assert_match(/async event sending failed: Boom!/, strio.string)
    assert_equal 1, @instance.client.transport.events.size
  end

  it "can merge various types of context" do
    @instance = Raven::Instance.new
    @instance.context.extra = { "baz" => "qux" }
    @instance.context.tags = { "sentry" => "is great" }
    @instance.context.user = { "id" => 1 }

    @instance.user_context("email" => "foo@example.com")
    @instance.tags_context("foo" => "bar")
    @instance.extra_context("sidekiq" => "true")

    assert_equal({ "id" => 1, "email" => "foo@example.com" }, @instance.context.user)
    assert_equal({ "foo" => "bar", "sentry" => "is great" }, @instance.context.tags)
    assert_equal "true", @instance.context.extra["sidekiq"]
    assert_equal "qux", @instance.context.extra["baz"]
  end
end
