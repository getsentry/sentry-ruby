# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::CaptureContext do
  # Records the current scope's trace_id every time it's called, so specs can
  # compare what a piece of middleware would see at different points in the stack.
  class CaptureContextSpecProbe
    def self.captured_trace_ids
      @captured_trace_ids ||= []
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      self.class.captured_trace_ids << Sentry.get_current_scope.get_trace_context[:trace_id]
      @app.call(env)
    end
  end

  describe "#call" do
    before do
      make_basic_app
    end

    it "establishes a propagation context and flags the env" do
      trace_id_in_app = nil

      app = lambda do |env|
        trace_id_in_app = Sentry.get_current_scope.get_trace_context[:trace_id]
        [200, {}, ["ok"]]
      end

      env = Rack::MockRequest.env_for("/test")
      described_class.new(app).call(env)

      expect(env[Sentry::PropagationContext::ESTABLISHED_ENV_KEY]).to eq(true)
      expect(trace_id_in_app).to be_a(String)
    end

    it "is a no-op when Sentry is not initialized" do
      allow(Sentry).to receive(:initialized?).and_return(false)

      called = false
      app = lambda do |env|
        called = true
        [200, {}, ["ok"]]
      end

      env = Rack::MockRequest.env_for("/test")
      described_class.new(app).call(env)

      expect(called).to eq(true)
      expect(env[Sentry::PropagationContext::ESTABLISHED_ENV_KEY]).to be_nil
    end
  end

  context "when composed with CaptureExceptions", type: :request do
    before do
      CaptureContextSpecProbe.captured_trace_ids.clear
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
      before do
        make_basic_app do |config, app|
          config.traces_sample_rate = 1.0
          app.config.middleware.insert_before(Sentry::Rails::CaptureExceptions, CaptureContextSpecProbe)
          app.config.middleware.insert_after(Sentry::Rails::CaptureExceptions, CaptureContextSpecProbe)
        end
      end

      it "keeps the same trace_id from before CaptureExceptions through the started transaction" do
        get "/world"

        early_trace_id, late_trace_id = CaptureContextSpecProbe.captured_trace_ids

        expect(early_trace_id).to be_a(String)
        # the "late" trace_id comes from the actual transaction CaptureExceptions started
        expect(late_trace_id).to eq(early_trace_id)
      end
    end
  end
end
