require 'spec_helper'
require 'raven/integrations/rack'

RSpec.describe Raven::Rack do
  let(:exception) { build_exception }
  let(:env) { Rack::MockRequest.env_for("/test") }

  context "when we expect to capture an exception" do
    before do
      expect(Raven::Rack).to receive(:capture_exception).with(exception, env)
    end

    it 'should capture exceptions' do
      app = ->(_e) { raise exception }
      stack = Raven::Rack.new(app)

      expect { stack.call(env) }.to raise_error(ZeroDivisionError)
    end

    it 'should capture rack.exception' do
      app = lambda do |e|
        e['rack.exception'] = exception
        [200, {}, ['okay']]
      end
      stack = Raven::Rack.new(app)

      stack.call(env)
    end

    it 'should capture sinatra errors' do
      app = lambda do |e|
        e['sinatra.error'] = exception
        [200, {}, ['okay']]
      end
      stack = Raven::Rack.new(app)

      stack.call(env)
    end
  end

  it 'should capture context and clear after app is called' do
    Raven::Context.current.tags[:environment] = :test

    app = ->(_e) { :ok }
    stack = Raven::Rack.new(app)

    stack.call(env)

    expect(Raven::Context.current.tags).to eq({})
  end

  it 'sets transaction' do
    app = lambda do |_e|
      expect(Raven.context.transaction.last).to eq "/test"
    end
    stack = Raven::Rack.new(app)

    stack.call(env)

    expect(Raven.context.transaction.last).to be_nil
  end

  it 'should allow empty rack env in rspec tests' do
    Raven.rack_context({}) # the rack env is empty when running rails/rspec tests
    Raven.capture_exception(build_exception)
  end

  it 'should bind request context' do
    Raven::Context.current.rack_env = nil

    app = lambda do |env|
      expect(Raven::Context.current.rack_env).to eq(env)

      ['response', {}, env]
    end
    stack = Raven::Rack.new(app)

    stack.call({})
  end

  it 'excludes non whitelisted params from rack env' do
    interface = Raven::HttpInterface.new
    additional_env = { "random_param" => "text", "query_string" => "test" }
    new_env = env.merge(additional_env)
    interface.from_rack(new_env)

    expect(interface.env).to_not include(additional_env)
  end

  it 'formats rack env according to the provided whitelist' do
    Raven.configuration.rack_env_whitelist = %w(random_param query_string)
    interface = Raven::HttpInterface.new
    additional_env = { "random_param" => "text", "query_string" => "test" }
    new_env = env.merge(additional_env)
    interface.from_rack(new_env)

    expect(interface.env).to eq(additional_env)
  end

  it 'keeps the original env intact when an empty whitelist is provided' do
    Raven.configuration.rack_env_whitelist = []
    interface = Raven::HttpInterface.new
    interface.from_rack(env)

    expect(interface.env).to eq(env)
  end

  it 'transforms headers to conform with the interface' do
    interface = Raven::HttpInterface.new
    new_env = env.merge("HTTP_VERSION" => "HTTP/1.1", "HTTP_COOKIE" => "test")
    interface.from_rack(new_env)

    expect(interface.headers).to eq("Content-Length" => "0", "Version" => "HTTP/1.1")
  end

  it 'puts cookies into the cookies attribute' do
    interface = Raven::HttpInterface.new
    new_env = env.merge("HTTP_COOKIE" => "test")
    interface.from_rack(new_env)

    expect(interface.cookies).to eq("test" => nil)
  end

  it 'does not ignore version headers which do not match SERVER_PROTOCOL' do
    new_env = env.merge("SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/2.0")

    interface = Raven::HttpInterface.new
    interface.from_rack(new_env)

    expect(interface.headers["Version"]).to eq("HTTP/2.0")
  end

  it 'retains any literal "HTTP-" in the actual header name' do
    interface = Raven::HttpInterface.new
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
    interface = Raven::HttpInterface.new

    expect { interface.from_rack(new_env) }.to_not raise_error
  end

  it 'should pass rack/lint' do
    app = proc do
      [200, { 'Content-Type' => 'text/plain' }, ['OK']]
    end

    stack = Raven::Rack.new(Rack::Lint.new(app))
    expect { stack.call(env) }.to_not raise_error
  end
end
