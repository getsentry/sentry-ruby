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

  before do
    perform_basic_setup
  end

  after do
    expect(Sentry.get_current_scope.rack_env).to eq({})
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:app) do
    lambda { |_| raise "app error" } # rubocop:disable Style/Lambda
  end

  let(:env) { {} }

  it "shows and captures the exception" do
    expect do
      expect(middleware.new(app).call(env)).to eq([500, "app error", {}])
    end.to change { transport.events.count }.by(1)
  end
end

RSpec.describe "Sentry::Rails::Overrides::DebugExceptionsCatcher" do
  context "using prepend" do
    before do
      middleware.send(:prepend, Sentry::Rails::Overrides::DebugExceptionsCatcher)
    end

    include_examples "exception catching middleware"
  end
end
