require 'spec_helper'

RSpec.describe Sentry::RackInterface do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

  before do
    Sentry.init do |config|
      config.dsn = 'dummy://12345:67890@sentry.localdomain/sentry/42'
    end
  end

  it 'excludes non whitelisted params from rack env' do
    interface = Sentry::HttpInterface.new
    additional_env = { "random_param" => "text", "query_string" => "test" }
    new_env = env.merge(additional_env)
    interface.from_rack(new_env)

    expect(interface.env).to_not include(additional_env)
  end

  it 'formats rack env according to the provided whitelist' do
    Sentry.configuration.rack_env_whitelist = %w(random_param query_string)
    interface = Sentry::HttpInterface.new
    additional_env = { "random_param" => "text", "query_string" => "test" }
    new_env = env.merge(additional_env)
    interface.from_rack(new_env)

    expect(interface.env).to eq(additional_env)
  end

  it 'keeps the original env intact when an empty whitelist is provided' do
    Sentry.configuration.rack_env_whitelist = []
    interface = Sentry::HttpInterface.new
    interface.from_rack(env)

    expect(interface.env).to eq(env)
  end

  describe 'format headers' do
    let(:additional_headers) { { "HTTP_VERSION" => "HTTP/1.1", "HTTP_COOKIE" => "test", "HTTP_X_REQUEST_ID" => "12345678" } }

    it 'transforms headers to conform with the interface' do
      interface = Sentry::HttpInterface.new
      interface.from_rack(env)

      expect(interface.headers).to eq("Content-Length" => "0", "Version" => "HTTP/1.1", "X-Request-Id" => "12345678")
    end

    context 'from Rails middleware' do
      let(:additional_headers) { { "action_dispatch.request_id" => "12345678" } }

      it 'transforms headers to conform with the interface' do
        interface = Sentry::HttpInterface.new
        interface.from_rack(env)

        expect(interface.headers).to eq("Content-Length" => "0", "X-Request-Id" => "12345678")
      end
    end
  end

  it 'puts cookies into the cookies attribute' do
    interface = Sentry::HttpInterface.new
    new_env = env.merge("HTTP_COOKIE" => "test")
    interface.from_rack(new_env)

    expect(interface.cookies).to eq("test" => nil)
  end

  it 'does not ignore version headers which do not match SERVER_PROTOCOL' do
    new_env = env.merge("SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/2.0")

    interface = Sentry::HttpInterface.new
    interface.from_rack(new_env)

    expect(interface.headers["Version"]).to eq("HTTP/2.0")
  end

  it 'retains any literal "HTTP-" in the actual header name' do
    interface = Sentry::HttpInterface.new
    new_env = env.merge("HTTP_HTTP_CUSTOM_HTTP_HEADER" => "test")
    interface.from_rack(new_env)

    expect(interface.headers).to include("Http-Custom-Http-Header" => "test")
  end

  it 'does not fail if an object in the env cannot be cast to string' do
    obj = Class.new do
      def to_s
        raise 'Could not stringify object!'
      end
    end.new

    new_env = env.merge("HTTP_FOO" => "BAR", "rails_object" => obj)
    interface = Sentry::HttpInterface.new

    expect { interface.from_rack(new_env) }.to_not raise_error
  end
end
