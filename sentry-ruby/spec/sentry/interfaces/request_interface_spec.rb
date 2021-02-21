return unless defined?(Rack)

require 'spec_helper'

RSpec.describe Sentry::RequestInterface do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }
  let(:interface) { described_class.build(env: env) }

  before do
    Sentry.init do |config|
      config.dsn = DUMMY_DSN
    end
  end

  describe "rack_env_whitelist" do
    it 'excludes non whitelisted params from rack env' do
      additional_env = { "random_param" => "text", "query_string" => "test" }
      new_env = env.merge(additional_env)
      interface = described_class.build(env: new_env)

      expect(interface.env).to_not include(additional_env)
    end

    it 'formats rack env according to the provided whitelist' do
      Sentry.configuration.rack_env_whitelist = %w(random_param query_string)
      additional_env = { "random_param" => "text", "query_string" => "test" }
      new_env = env.merge(additional_env)
      interface = described_class.build(env: new_env)

      expect(interface.env).to eq(additional_env)
    end

    it 'keeps the original env intact when an empty whitelist is provided' do
      Sentry.configuration.rack_env_whitelist = []
      interface = described_class.build(env: env)

      expect(interface.env).to eq(env)
    end
  end

  describe 'format headers' do
    let(:additional_headers) { { "HTTP_VERSION" => "HTTP/1.1", "HTTP_COOKIE" => "test", "HTTP_X_REQUEST_ID" => "12345678" } }

    it 'transforms headers to conform with the interface' do
      interface = described_class.build(env: env)

      expect(interface.headers).to eq("Content-Length" => "0", "Version" => "HTTP/1.1", "X-Request-Id" => "12345678")
    end

    context 'from Rails middleware' do
      let(:additional_headers) { { "action_dispatch.request_id" => "12345678" } }

      it 'transforms headers to conform with the interface' do
        interface = described_class.build(env: env)

        expect(interface.headers).to eq("Content-Length" => "0", "X-Request-Id" => "12345678")
      end
    end

    context 'with additional env variables' do
      let(:mock) { double }
      let(:env) { { "some.variable" => mock } }

      it 'does not call #to_s for unnecessary env variables' do
        expect(mock).not_to receive(:to_s)

        interface = described_class.build(env: env)
      end
    end
  end

  it "doesn't capture cookies info" do
    new_env = env.merge(
      ::Rack::RACK_REQUEST_COOKIE_HASH => "cookies!"
    )

    interface = described_class.build(env: new_env)

    expect(interface.cookies).to eq(nil)
    expect(interface.env["COOKIE"]).to eq(nil)
  end

  describe "headers filtering" do
    it "filters out HTTP_COOKIE header" do
      new_env = env.merge(
        "HTTP_COOKIE" => "cookies!"
      )

      interface = described_class.build(env: new_env)

      expect(interface.headers["Cookie"]).to eq(nil)
    end

    it "filters out non-http headers" do
      expect(interface.headers["Request-Method"]).to eq(nil)
    end

    it "doesn't filter out CONTENT_TYPE or CONTENT_LENGTH headers" do
      new_env = env.merge(
        "CONTENT_LENGTH" => 10,
        "CONTENT_TYPE" => "text/html"
      )

      interface = described_class.build(env: new_env)

      expect(interface.headers["Content-Length"]).to eq("10")
      expect(interface.headers["Content-Type"]).to eq("text/html")
    end

    it 'does not ignore version headers which do not match SERVER_PROTOCOL' do
      new_env = env.merge("SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/2.0")

      interface = described_class.build(env: new_env)

      expect(interface.headers["Version"]).to eq("HTTP/2.0")
    end

    it 'retains any literal "HTTP-" in the actual header name' do
      new_env = env.merge("HTTP_HTTP_CUSTOM_HTTP_HEADER" => "test")
      interface = described_class.build(env: new_env)

      expect(interface.headers).to include("Http-Custom-Http-Header" => "test")
    end

    it 'does not fail if an object in the env cannot be cast to string' do
      obj = Class.new do
        def to_s
          raise 'Could not stringify object!'
        end
      end.new

      new_env = env.merge("HTTP_FOO" => "BAR", "rails_object" => obj)

      expect { interface = described_class.build(env: new_env) }.to_not raise_error
    end
  end

  context "with form data" do
    it "doesn't store request body by default" do
      new_env = env.merge(
        "REQUEST_METHOD" => "POST",
        ::Rack::RACK_INPUT => StringIO.new("data=ignore me")
      )

      interface = described_class.build(env: new_env)

      expect(interface.data).to eq(nil)
    end
  end

  context "with request body" do
    it "doesn't store request body by default" do
      new_env = env.merge(::Rack::RACK_INPUT => StringIO.new("ignore me"))

      interface = described_class.build(env: new_env)

      expect(interface.data).to eq(nil)
    end
  end

  context "with config.send_default_pii = true" do
    before do
      Sentry.configuration.send_default_pii = true
    end

    it "stores cookies" do
      new_env = env.merge(
        ::Rack::RACK_REQUEST_COOKIE_HASH => "cookies!"
      )

      interface = described_class.build(env: new_env)

      expect(interface.cookies).to eq("cookies!")
    end

    it "stores form data" do
      new_env = env.merge(
        "REQUEST_METHOD" => "POST",
        ::Rack::RACK_INPUT => StringIO.new("data=catch me")
      )

      interface = described_class.build(env: new_env)

      expect(interface.data).to eq({ "data" => "catch me" })
    end

    it "stores request body" do
      new_env = env.merge(::Rack::RACK_INPUT => StringIO.new("catch me"))

      interface = described_class.build(env: new_env)

      expect(interface.data).to eq("catch me")
    end

    it "doesn't remove ip address headers" do
      ip = "1.1.1.1"

      env.merge!(
        "REMOTE_ADDR" => ip,
        "HTTP_CLIENT_IP" => ip,
        "HTTP_X_REAL_IP" => ip,
        "HTTP_X_FORWARDED_FOR" => ip
      )

      interface = described_class.build(env: env)

      expect(interface.env).to include("REMOTE_ADDR")
      expect(interface.headers.keys).to include("Client-Ip")
      expect(interface.headers.keys).to include("X-Real-Ip")
      expect(interface.headers.keys).to include("X-Forwarded-For")
    end
  end
end
