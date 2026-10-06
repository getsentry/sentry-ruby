# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::CaptureContext do
  class CaptureContextSpecProbe
    def self.captured_trace_ids
      @captured_trace_ids ||= []
    end

    def self.captured_span_ids
      @captured_span_ids ||= []
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      trace_context = Sentry.get_current_scope.get_trace_context
      self.class.captured_trace_ids << trace_context[:trace_id]
      self.class.captured_span_ids << trace_context[:span_id]
      @app.call(env)
    end
  end

  describe "#call" do
    before do
      make_basic_app
    end

    def propagation_context_in_app(env)
      context_in_app = nil

      app = lambda do |_env|
        context_in_app = Sentry.get_current_scope.propagation_context
        [200, {}, ["ok"]]
      end

      described_class.new(app).call(env)

      context_in_app
    end

    it "starts a new trace for every request served by the same thread" do
      first = propagation_context_in_app(Rack::MockRequest.env_for("/test"))
      second = propagation_context_in_app(Rack::MockRequest.env_for("/test"))

      expect(second.trace_id).not_to eq(first.trace_id)
    end
  end

  context "when composed with CaptureExceptions", type: :request do
    before do
      CaptureContextSpecProbe.captured_trace_ids.clear
      CaptureContextSpecProbe.captured_span_ids.clear
    end

    context "without tracing enabled" do
      before do
        make_basic_app do |config, app|
          app.config.middleware.insert_before(Sentry::Rails::CaptureExceptions, CaptureContextSpecProbe)
          app.config.middleware.insert_after(Sentry::Rails::CaptureExceptions, CaptureContextSpecProbe)
        end
      end

      it "keeps the same trace_id before and after CaptureExceptions runs" do
        get "/world"

        early_trace_id, late_trace_id = CaptureContextSpecProbe.captured_trace_ids

        expect(early_trace_id).to be_a(String)
        expect(late_trace_id).to eq(early_trace_id)
      end
    end

    context "with tracing enabled" do
      let(:transport) { Sentry.get_current_client.transport }

      before do
        make_basic_app do |config, app|
          config.traces_sample_rate = 1.0
          app.config.middleware.insert_before(Sentry::Rails::CaptureExceptions, CaptureContextSpecProbe)
          app.config.middleware.insert_after(Sentry::Rails::CaptureExceptions, CaptureContextSpecProbe)
        end
      end

      it "points a span_id captured before CaptureExceptions at the started transaction" do
        get "/world"

        transaction = transport.events.last
        early_span_id = CaptureContextSpecProbe.captured_span_ids.first

        expect(early_span_id).to eq(transaction.contexts.dig(:trace, :span_id))
      end

      it "keeps the same trace_id from before CaptureExceptions through the started transaction" do
        get "/world"

        early_trace_id, late_trace_id = CaptureContextSpecProbe.captured_trace_ids

        expect(early_trace_id).to be_a(String)
        expect(late_trace_id).to eq(early_trace_id)
      end

      it "continues the incoming trace" do
        incoming_transaction = Sentry::Transaction.new(op: "pageload", status: "ok", sampled: true, name: "a/path")

        get "/world", headers: { "sentry-trace" => incoming_transaction.to_sentry_trace }

        trace = transport.events.last.contexts[:trace]
        expect(trace[:trace_id]).to eq(incoming_transaction.trace_id)
        expect(trace[:parent_span_id]).to eq(incoming_transaction.span_id)
        expect(CaptureContextSpecProbe.captured_trace_ids.first).to eq(incoming_transaction.trace_id)
      end
    end
  end
end
