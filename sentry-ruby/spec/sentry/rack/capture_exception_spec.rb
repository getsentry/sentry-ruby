require 'spec_helper'

RSpec.describe Sentry::Rack::CaptureException do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

  before do
    Sentry.init do |config|
      config.breadcrumbs_logger = [:sentry_logger]
      config.dsn = DUMMY_DSN
      config.transport.transport_class = Sentry::DummyTransport
    end
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it 'captures the exception from direct raise' do
    app = ->(_e) { raise exception }
    stack = described_class.new(app)

    expect { stack.call(env) }.to raise_error(ZeroDivisionError)

    event = transport.events.last
    expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
  end

  it 'captures the exception from rack.exception' do
    app = lambda do |e|
      e['rack.exception'] = exception
      [200, {}, ['okay']]
    end
    stack = described_class.new(app)

    expect do
      stack.call(env)
    end.to change { transport.events.count }.by(1)

    event = transport.events.last
    expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
  end

  it 'captures the exception from sinatra.error' do
    app = lambda do |e|
      e['sinatra.error'] = exception
      [200, {}, ['okay']]
    end
    stack = described_class.new(app)

    stack.call(env)

    expect do
      stack.call(env)
    end.to change { transport.events.count }.by(1)

    event = transport.events.last
    expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
  end

  it 'sets the transaction and rack env' do
    app = lambda do |e|
      e['rack.exception'] = exception
      [200, {}, ['okay']]
    end
    stack = described_class.new(app)

    stack.call(env)

    event = transport.events.last
    expect(event.transaction).to eq("/test")
    expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    expect(Sentry.get_current_scope.transaction_names).to be_empty
    expect(Sentry.get_current_scope.rack_env).to eq({})
  end

  it 'passes rack/lint' do
    app = proc do
      [200, { 'Content-Type' => 'text/plain' }, ['OK']]
    end

    stack = described_class.new(Rack::Lint.new(app))
    expect { stack.call(env) }.to_not raise_error
  end

  describe "state encapsulation" do
    before do
      Sentry.configure_scope { |s| s.set_tags(tag_1: "don't change me") }
    end

    it "only contains the breadcrumbs of the request" do
      logger = ::Logger.new(nil)

      logger.info("old breadcrumb")

      request_1 = lambda do |e|
        logger.info("request breadcrumb")
        Sentry.capture_message("test")
      end

      app_1 = described_class.new(request_1)

      app_1.call(env)

      event = transport.events.last
      expect(event.breadcrumbs.count).to eq(1)
      expect(event.breadcrumbs.peek.message).to eq("request breadcrumb")
    end
    it "doesn't pollute the top-level scope" do
      request_1 = lambda do |e|
        Sentry.configure_scope { |s| s.set_tags({tag_1: "foo"}) }
        Sentry.capture_message("test")
      end
      app_1 = described_class.new(request_1)

      app_1.call(env)

      event = transport.events.last
      expect(event.tags).to eq(tag_1: "foo")
      expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
    end
    it "doesn't pollute other request's scope" do
      request_1 = lambda do |e|
        Sentry.configure_scope { |s| s.set_tags({tag_1: "foo"}) }
        e['rack.exception'] = exception
      end
      app_1 = described_class.new(request_1)
      app_1.call(env)

      event = transport.events.last
      expect(event.tags).to eq(tag_1: "foo")
      expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")

      request_2 = proc do |e|
        Sentry.configure_scope { |s| s.set_tags({tag_2: "bar"}) }
        e['rack.exception'] = exception
      end
      app_2 = described_class.new(request_2)
      app_2.call(env)

      event = transport.events.last
      expect(event.tags).to eq(tag_2: "bar")
      expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
    end
  end
end

