require 'spec_helper'
require 'raven/integrations/rails/middleware/debug_exceptions_catcher'

describe Raven::Rails::Middleware::DebugExceptionsCatcher do
  let(:middleware) do
    Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue => e
        render_exception(env, e)
      end

      def render_exception(_, exception)
        [500, exception.message, {}]
      end
    end
  end

  let(:app) do
    lambda { |_| raise "app error" } # rubocop:disable Style/Lambda
  end

  let(:env) { {} }

  shared_examples "the debug exceptions middleware" do
    it "shows the exception" do
      expect(middleware.new(app).call(env)).to eq([500, "app error", {}])
    end

    it "captures the exception" do
      expect(Raven::Rack).to receive(:capture_exception)
      middleware.new(app).call(env)
    end

    context "when an error is raised" do
      it "shows the original exception" do
        allow(Raven::Rack).to receive(:capture_exception).and_raise("raven error")
        expect(middleware.new(app).call(env)).to eq([500, "app error", {}])
      end
    end

    context "when catch_debugged_exceptions is disabled" do
      before do
        Raven.configure do |config|
          config.catch_debugged_exceptions = false
        end
      end

      after do
        Raven.configure do |config|
          config.catch_debugged_exceptions = true
        end
      end

      it "doesn't capture the exception" do
        expect(Raven::Rack).not_to receive(:capture_exception)
        middleware.new(app).call(env)
      end
    end
  end

  context "using include" do
    before do
      middleware.send(:include, Raven::Rails::Middleware::OldDebugExceptionsCatcher)
    end

    it_behaves_like "the debug exceptions middleware"
  end

  context "using prepend" do
    before do
      skip "prepend not available" unless middleware.respond_to?(:prepend, true)
      middleware.send(:prepend, Raven::Rails::Middleware::DebugExceptionsCatcher)
    end

    it_behaves_like "the debug exceptions middleware"
  end
end
