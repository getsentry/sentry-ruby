require 'spec_helper'

RSpec.describe Sentry::Rack::Tracing do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

  before do
    Sentry.init do |config|
      config.breadcrumbs_logger = [:sentry_logger]
      config.dsn = DUMMY_DSN
      config.transport.transport_class = Sentry::DummyTransport
      config.traces_sample_rate = 1.0
    end
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "starts a span and finishes it" do
    app = ->(_) do
      [200, {}, ["ok"]]
    end

    stack = described_class.new(app)

    stack.call(env)

    transaction = transport.events.last
    expect(transaction.type).to eq("transaction")
    expect(transaction.timestamp).not_to be_nil
    expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
    expect(transaction.contexts.dig(:trace, :op)).to eq("rack.request")
    expect(transaction.spans.count).to eq(0)
  end

  context "when there's an exception" do
    it "still finishes the transaction" do
      app = ->(_) do
        raise "foo"
      end

      app = Sentry::Rack::CaptureException.new(app)
      stack = described_class.new(app)

      expect do
        stack.call(env)
      end.to raise_error("foo")

      expect(transport.events.count).to eq(2)
      event = transport.events.first
      transaction = transport.events.last
      expect(event.contexts.dig(:trace, :trace_id).length).to eq(32)
      expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))


      expect(transaction.type).to eq("transaction")
      expect(transaction.timestamp).not_to be_nil
      expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
      expect(transaction.contexts.dig(:trace, :op)).to eq("rack.request")
      expect(transaction.spans.count).to eq(0)
    end
  end

  context "when traces_sample_rate is not set" do
    before do
      Sentry.configuration.traces_sample_rate = nil
    end

    it "doesn't record transaction" do
      app = ->(_) do
        [200, {}, ["ok"]]
      end

      stack = described_class.new(app)

      stack.call(env)

      expect(transport.events.count).to eq(0)
    end
  end
end

