require "spec_helper"
require "fakeredis"

RSpec.describe Sentry::Redis::Client do
  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end
  let(:redis) do
    Redis.new
  end

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.transport.transport_class = Sentry::HTTPTransport
        config.logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = 'http://foobarbaz@o447951.ingest.sentry.io/5434472'
      end
    end

    context "with config.send_default_pii = true" do
      before do
        Sentry.configuration.send_default_pii = true
      end

      it "records the request's span with query string" do
        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        redis.set("key", "value")

        request_span = transaction.span_recorder.spans.last
        expect(request_span.op).to eq("redis")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("set key")
        expect(request_span.data).to eq({ server: "127.0.0.1:6379/0" })
      end
    end
  end
end
