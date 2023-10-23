require "puma"
require_relative "../spec_helper"

# Because puma doesn't have any dependency, if Rack is not installed the entire test won't work
return if ENV["RACK_VERSION"] == "0"

SimpleCov.command_name "RSpecIsolated"

RSpec.describe Puma::Server do
  class TestServer
    def initialize(app, options)
      @host = "127.0.0.1"
      @ios = []
      @server = Puma::Server.new(app, nil, options)
      @port = (@server.add_tcp_listener @host, 0).addr[1]
      @server.run
    end

    def send_http_and_read(req)
      (new_connection << req).read
    end

    def new_connection
      TCPSocket.new(@host, @port).tap {|sock| @ios << sock}
    end

    def close
      @server.stop(true)
      @ios.each { |io| io.close }
    end
  end

  let(:app) do
    proc { raise "foo" }
  end

  def server_run(app, lowlevel_error_handler: nil, &block)
    server = TestServer.new(app, lowlevel_error_handler: lowlevel_error_handler)
    yield server
  ensure
    server.close
  end

  before do
    perform_basic_setup
  end

  it "captures low-level errors" do
    res = server_run(app) do |server|
      server.send_http_and_read("GET / HTTP/1.0\r\n\r\n")
    end
    expect(res).to match(/500 Internal Server Error/)
    events = sentry_events
    expect(events.count).to eq(1)
    event = events.first
    expect(event.exception.values.first.value).to match("foo")
  end

  context "when user defines lowlevel_error_handler" do
    it "captures low-level errors" do
      handler_executed = false

      lowlevel_error_handler = ->(e, env) do
        handler_executed = true
        # Due to the way we test Puma::Server, we won't be verify this response
        [500, {}, ["Error is handled"]]
      end

      res = server_run(app, lowlevel_error_handler: lowlevel_error_handler) do |server|
        server.send_http_and_read("GET / HTTP/1.0\r\n\r\n")
      end

      expect(res).to match(/500 Internal Server Error/)
      expect(handler_executed).to eq(true)
      events = sentry_events
      expect(events.count).to eq(1)
      event = events.first
      expect(event.exception.values.first.value).to match("foo")
    end
  end

  context "when puma raises its own errors" do
    [Puma::MiniSSL::SSLError, Puma::HttpParserError, Puma::HttpParserError501].each do |error_class|
      it "doesn't capture #{error_class}" do
        app = proc { raise error_class.new("foo") }

        res = server_run(app) do |server|
          server.send_http_and_read("GET / HTTP/1.0\r\n\r\n")
        end

        expect(res).to match(/500 Internal Server Error/)
        events = sentry_events
        expect(events.count).to eq(0)
      end

      it "captures #{error_class} when it is removed from the SDK's config.excluded_exceptions" do
        Sentry.configuration.excluded_exceptions.delete(error_class.name)

        app = proc { raise error_class.new("foo") }

        res = server_run(app) do |server|
          server.send_http_and_read("GET / HTTP/1.0\r\n\r\n")
        end

        expect(res).to match(/500 Internal Server Error/)
        events = sentry_events
        expect(events.count).to eq(1)
        event = events.first
        expect(event.exception.values.first.type).to match(error_class.name)
        expect(event.exception.values.first.value).to match("foo")
      end
    end
  end

  context "when Sentry.capture_exception causes error" do
    it "doesn't affect the response" do
      expect(Sentry).to receive(:capture_exception).and_raise("bar")

      res = server_run(app) do |server|
        server.send_http_and_read("GET / HTTP/1.0\r\n\r\n")
      end

      expect(res).to match(/500 Internal Server Error/)
      expect(sentry_events).to be_empty
    end
  end
end
