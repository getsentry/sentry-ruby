require 'spec_helper'
require "sentry/rails/controller_methods"

RSpec.describe Sentry::Rails::ControllerMethods do
  include described_class

  def request
    double(env: Rack::MockRequest.env_for("/test", {}))
  end

  before do
    perform_basic_setup
  end

  let(:options) do
    { tags: { new_tag: true }}
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  after do
    # make sure the scope isn't polluted
    expect(Sentry.get_current_scope.tags).to eq({})
    expect(Sentry.get_current_scope.rack_env).to eq({})
  end

  describe "#capture_message" do
    let(:message) { "foo" }

    it "captures a message with the request environment" do
      capture_message(message, options)

      event = transport.events.last
      expect(event.message).to eq("foo")
      expect(event.tags).to eq({ new_tag: true })
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    end
  end

  describe "#capture_exception" do
    let(:exception) { ZeroDivisionError.new("divided by 0") }

    it "captures a exception with the request environment" do
      capture_exception(exception, options)

      event = transport.events.last
      expect(event.tags).to eq({ new_tag: true })
      expect(event.to_hash.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    end
  end
end
