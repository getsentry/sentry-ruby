return unless defined?(Rack)

require 'spec_helper'

RSpec.describe Sentry::RequestInterface do
  let(:env) { Rack::MockRequest.env_for("/test") }
  let(:send_default_pii) { false }
  let(:rack_env_whitelist) { Sentry::Configuration::RACK_ENV_WHITELIST_DEFAULT }

  subject do
    described_class.new(env: env, send_default_pii: send_default_pii, rack_env_whitelist: rack_env_whitelist)
  end

  describe "rack_env_whitelist" do
    let(:additional_env) { { "random_param" => "text", "query_string" => "test" } }

    before do
      env.merge!(additional_env)
    end

    it 'excludes non whitelisted params from rack env' do
      expect(subject.env).to_not include(additional_env)
    end

    context "with provided whitelist" do
      let(:rack_env_whitelist) { %w(random_param query_string) }

      it 'formats rack env according to the provided whitelist' do
        expect(subject.env).to eq(additional_env)
      end
    end

    context "with empty whitelist" do
      let(:rack_env_whitelist) { [] }

      it 'keeps the original env intact' do
        expect(subject.env).to eq(env)
      end
    end
  end

  describe 'format headers' do
    let(:additional_headers) { { "HTTP_VERSION" => "HTTP/1.1", "HTTP_COOKIE" => "test", "HTTP_X_REQUEST_ID" => "12345678" } }
    let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

    it 'transforms headers to conform with the interface' do
      expect(subject.headers).to eq("Content-Length" => "0", "Version" => "HTTP/1.1", "X-Request-Id" => "12345678")
    end

    context 'from Rails middleware' do
      let(:additional_headers) { { "action_dispatch.request_id" => "12345678" } }

      it 'transforms headers to conform with the interface' do
        expect(subject.headers).to eq("Content-Length" => "0", "X-Request-Id" => "12345678")
      end
    end

    context 'with special characters' do
      let(:additional_headers) { { "HTTP_FOO" => "Tekirda\xC4" } }

      it "doesn't cause any issue" do
        json = JSON.generate(subject.to_hash)

        expect(JSON.parse(json)["headers"]).to eq({"Content-Length"=>"0", "Foo"=>"Tekirda�"})
      end
    end

    context 'with additional env variables' do
      let(:mock) { double }
      let(:env) { { "some.variable" => mock } }

      it 'does not call #to_s for unnecessary env variables' do
        expect(mock).not_to receive(:to_s)

        subject
      end
    end
  end

  it "doesn't capture cookies info" do
    env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => "cookies!")

    expect(subject.cookies).to eq(nil)
    expect(subject.env["COOKIE"]).to eq(nil)
  end

  describe "headers filtering" do
    it "filters out HTTP_COOKIE header" do
      env.merge!("HTTP_COOKIE" => "cookies!")

      expect(subject.headers["Cookie"]).to eq(nil)
    end

    it "filters out non-http headers" do
      expect(subject.headers["Request-Method"]).to eq(nil)
    end

    it "doesn't filter out CONTENT_TYPE or CONTENT_LENGTH headers" do
      env.merge!(
        "CONTENT_LENGTH" => 10,
        "CONTENT_TYPE" => "text/html"
      )

      expect(subject.headers["Content-Length"]).to eq("10")
      expect(subject.headers["Content-Type"]).to eq("text/html")
    end

    it 'does not ignore version headers which do not match SERVER_PROTOCOL' do
      env.merge!("SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/2.0")

      expect(subject.headers["Version"]).to eq("HTTP/2.0")
    end

    it 'retains any literal "HTTP-" in the actual header name' do
      env.merge!("HTTP_HTTP_CUSTOM_HTTP_HEADER" => "test")
      expect(subject.headers).to include("Http-Custom-Http-Header" => "test")
    end

    it "skips Authorization header" do
      env.merge!("HTTP_AUTHORIZATION" => "Basic YWxhZGRpbjpvcGVuc2VzYW1l")

      expect(subject.headers["Authorization"]).to eq(nil)
    end

    it 'does not fail if an object in the env cannot be cast to string' do
      obj = Class.new do
        def to_s
          raise 'Could not stringify object!'
        end
      end.new

      env.merge!("HTTP_FOO" => "BAR", "rails_object" => obj)

      expect { described_class.new(env: env, send_default_pii: send_default_pii, rack_env_whitelist: rack_env_whitelist) }.to_not raise_error
    end
  end

  it "doesn't store request body by default" do
    env.merge!("REQUEST_METHOD" => "POST", ::Rack::RACK_INPUT => StringIO.new("data=ignore me"))

    expect(subject.data).to eq(nil)
  end

  it "doesn't store request body by default" do
    env.merge!(::Rack::RACK_INPUT => StringIO.new("ignore me"))

    expect(subject.data).to eq(nil)
  end

  it "doesn't store query_string by default" do
    env.merge!("QUERY_STRING" => "token=xxxx")

    expect(subject.query_string).to eq(nil)
  end

  context "with config.send_default_pii = true" do
    let(:send_default_pii) { true }

    it "stores cookies" do
      env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => "cookies!")

      expect(subject.cookies).to eq("cookies!")
    end

    it "stores form data" do
      env.merge!("REQUEST_METHOD" => "POST", ::Rack::RACK_INPUT => StringIO.new("data=catch me"))

      expect(subject.data).to eq({ "data" => "catch me" })
    end

    it "stores query string" do
      env.merge!("QUERY_STRING" => "token=xxxx")

      expect(subject.query_string).to eq("token=xxxx")
    end

    it "stores request body" do
      env.merge!(::Rack::RACK_INPUT => StringIO.new("catch me"))

      expect(subject.data).to eq("catch me")
    end

    it "stores Authorization header" do
      env.merge!("HTTP_AUTHORIZATION" => "Basic YWxhZGRpbjpvcGVuc2VzYW1l")

      expect(subject.headers["Authorization"]).to eq("Basic YWxhZGRpbjpvcGVuc2VzYW1l")
    end

    it "force encodes request body to avoid encoding issue" do
      env.merge!(::Rack::RACK_INPUT => StringIO.new("あ"))

      expect do
        JSON.generate(subject.to_hash)
      end.not_to raise_error
    end

    it "doesn't remove ip address headers" do
      ip = "1.1.1.1"

      env.merge!(
        "REMOTE_ADDR" => ip,
        "HTTP_CLIENT_IP" => ip,
        "HTTP_X_REAL_IP" => ip,
        "HTTP_X_FORWARDED_FOR" => ip
      )

      expect(subject.env).to include("REMOTE_ADDR")
      expect(subject.headers.keys).to include("Client-Ip")
      expect(subject.headers.keys).to include("X-Real-Ip")
      expect(subject.headers.keys).to include("X-Forwarded-For")
    end
  end
end
