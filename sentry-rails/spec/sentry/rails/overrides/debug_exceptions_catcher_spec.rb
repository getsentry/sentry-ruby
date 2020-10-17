require 'spec_helper'
require 'sentry/rails/overrides/debug_exceptions_catcher'

RSpec.shared_examples "exception catching middleware" do
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

  it "shows the exception" do
    expect(middleware.new(app).call(env)).to eq([500, "app error", {}])
  end

  it "captures the exception" do
    expect(Sentry::Rack).to receive(:capture_exception)
    middleware.new(app).call(env)
  end

  context "when an error is raised" do
    it "shows the original exception" do
      allow(Sentry::Rack).to receive(:capture_exception).and_raise("raven error")
      expect(middleware.new(app).call(env)).to eq([500, "app error", {}])
    end
  end
end

RSpec.describe "Sentry::Rails::Overrides::DebugExceptionsCatcher" do
  if Class.respond_to?(:alias_method_chain)
    context "using include" do
      before do
        middleware.send(:include, Sentry::Rails::Overrides::OldDebugExceptionsCatcher)
      end

      include_examples "exception catching middleware"
    end
  end

  if Class.respond_to?(:prepend)
    context "using prepend" do
      before do
        middleware.send(:prepend, Sentry::Rails::Overrides::DebugExceptionsCatcher)
      end

      include_examples "exception catching middleware"
    end
  end
end
