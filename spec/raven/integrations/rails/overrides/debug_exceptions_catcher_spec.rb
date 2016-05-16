require 'spec_helper'
require 'raven/integrations/rails/overrides/debug_exceptions_catcher'

describe Raven::Rails::Overrides::DebugExceptionsCatcher do
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

  context "using include" do
    before do
      middleware.send(:include, Raven::Rails::Overrides::OldDebugExceptionsCatcher)
    end

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
  end

  context "using prepend" do
    before do
      skip "prepend not available" unless middleware.respond_to?(:prepend, true)
      middleware.send(:prepend, Raven::Rails::Overrides::DebugExceptionsCatcher)
    end

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
  end
end
