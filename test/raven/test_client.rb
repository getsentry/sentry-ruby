require "test_helper"

class TestClient < Raven::Test
  def setup
    @client = Raven::Client.new(Raven.configuration.dup)
    @event  = Raven::Event.new
  end

  it "doesnt send an event if sending is not allowed" do
    assert @client.configuration.sending_allowed?(@event)
    config = @client.configuration
    def config.sending_allowed?(_event); false; end

    refute @client.send_event(@event)
  end

  it "doesn't send an event if client state is failed" do
    state = Raven::ClientState.new
    state.failure
    @client.instance_variable_set(:@state, state)

    refute @client.send_event(@event)
  end

  it "returns the event hash when successful" do
    event = @client.send_event(@event)
    assert_equal @event.to_hash, event
  end

  it "logs while sending" do
    stringio = StringIO.new
    log = Raven::Logger.new(stringio)
    @client.configuration.logger = log

    @client.send_event(@event)

    assert_match(/Sending event [0-9a-f]+ to Sentry$/, stringio.string)
  end

  it "sends an encoded event via the transport" do
    @client.send_event(@event)
    auth_header = @client.transport.events.first[0]

    assert_match(/sentry_version/, auth_header)
    assert_match(/sentry_client/, auth_header)
    assert_match(/sentry_timestamp/, auth_header)
    assert_match(/sentry_key/, auth_header)
    assert_match(/sentry_secret/, auth_header)

    evt = @client.transport.events.first[1]
    assert_equal @event.environment, JSON.parse(evt)["environment"]
  end

  it "sends a hash that looks like a Raven::Event" do
    hash = @event.to_hash

    event = @client.send_event(hash)

    assert_equal @event.to_hash, event
  end

  it "sets transport based on config scheme" do
    @client.configuration = Raven::Configuration.new.tap { |c| c.dsn = "https://" }
    assert_instance_of Raven::Transports::HTTP, @client.transport

  end

  it "sets dummy based on dsn" do
    @client.configuration = Raven::Configuration.new.tap { |c| c.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42" }
    assert_instance_of Raven::Transports::Dummy, @client.transport
  end

  it "raises if scheme is unrecognized" do
    assert_raises Raven::Error do
      @client.configuration = Raven::Configuration.new.tap { |c| c.scheme = "flarp" }
      @client.transport
    end
  end

  it "can gzip the event" do
    @client.configuration.encoding = "gzip"
    @client.send_event(@event)

    base64 = @client.transport.events.first[1]
    gzip = Base64.strict_decode64(base64)
    evt = Zlib::Inflate.inflate(gzip)
    assert_equal @event.environment, JSON.parse(evt)["environment"]
  end

  it "sets the client state to failure on a failed send" do
    @mock = Minitest::Mock.new
    @mock.expect :should_try?, true
    @mock.expect :failure, true
    transport = @client.transport
    def transport.send_event(*); raise "Boom!"; end
    @client.instance_variable_set(:@state, @mock)

    refute @client.send_event(@event)

    @mock.verify
  end

  it "sets client state to success" do
    @mock = Minitest::Mock.new
    @mock.expect :should_try?, true
    @mock.expect :success, true
    @client.instance_variable_set(:@state, @mock)

    assert @client.send_event(@event)

    @mock.verify
  end

  it "sets the client state to failure if cannot try to send" do
    @mock = Minitest::Mock.new
    @mock.expect :should_try?, false
    @mock.expect :failure, true
    @client.instance_variable_set(:@state, @mock)

    refute @client.send_event(@event)

    @mock.verify
  end

  it "sends event and exception to the transport_failure_callback" do
    event = nil
    exception = nil
    transport = @client.transport
    def transport.send_event(*); raise Raven::Error, "Boom!"; end
    @client.configuration.transport_failure_callback = Proc.new { |e, exc| event = e; exception = exc }

    refute @client.send_event(@event)

    assert_instance_of Hash, event
    assert_instance_of Raven::Error, exception
  end

  it "logs some stuff on a failed send" do
    @event.message = "Test message"
    stringio = StringIO.new
    log = Raven::Logger.new(stringio)
    @client.configuration.logger = log
    transport = @client.transport
    def transport.send_event(*); raise Raven::Error, "Boom!"; end

    refute @client.send_event(@event)

    assert_match(/Unable to record event with remote/, stringio.string)
    assert_match("Failed to submit event: #{@event.message}", stringio.string)
  end

  it "logs differently if we're not trying due to previous failure" do
    stringio = StringIO.new
    log = Raven::Logger.new(stringio)
    @client.configuration.logger = log
    @mock = Minitest::Mock.new
    @mock.expect :should_try?, false
    @mock.expect :failure, true
    @client.instance_variable_set(:@state, @mock)

    refute @client.send_event(@event)

    assert_match("Not sending event due to previous failure(s).", stringio.string)
  end
end
