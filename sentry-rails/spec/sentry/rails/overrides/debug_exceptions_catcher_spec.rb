require 'spec_helper'

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

RSpec.describe "Raven::Rails::Overrides::DebugExceptionsCatcher", :rails => true do
  before(:all) do
    require 'raven/integrations/rails/overrides/debug_exceptions_catcher'
  end

  if Class.respond_to?(:alias_method_chain)
    context "using include" do
      before do
        middleware.send(:include, Raven::Rails::Overrides::OldDebugExceptionsCatcher)
      end

      include_examples "exception catching middleware"
    end
  end

  if Class.respond_to?(:prepend)
    context "using prepend" do
      before do
        middleware.send(:prepend, Raven::Rails::Overrides::DebugExceptionsCatcher)
      end

      include_examples "exception catching middleware"
    end
  end
end
