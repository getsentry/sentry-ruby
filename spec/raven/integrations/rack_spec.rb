require 'spec_helper'
require 'raven/integrations/rack'

describe Raven::Rack do
  it 'should capture exceptions' do
    exception = build_exception
    env = {}

    expect(Raven::Rack).to receive(:capture_exception).with(exception, env)

    app = ->(_e) { raise exception }

    stack = Raven::Rack.new(app)
    expect { stack.call(env) }.to raise_error(ZeroDivisionError)
  end

  it 'should capture rack.exception' do
    exception = build_exception
    env = {}

    expect(Raven::Rack).to receive(:capture_exception).with(exception, env)

    app = lambda do |e|
      e['rack.exception'] = exception
      [200, {}, ['okay']]
    end

    stack = Raven::Rack.new(app)

    stack.call(env)
  end

  it 'should capture sinatra errors' do
    exception = build_exception
    env = {}

    expect(Raven::Rack).to receive(:capture_exception).with(exception, env)

    app = lambda do |e|
      e['sinatra.error'] = exception
      [200, {}, ['okay']]
    end

    stack = Raven::Rack.new(app)

    stack.call(env)
  end

  it 'should clear context after app is called' do
    Raven::Context.current.tags[:environment] = :test

    app = ->(env) { ['response', {}, env] }
    stack = Raven::Rack.new(app)

    stack.call({})

    expect(Raven::Context.current.tags).to eq({})
  end

  it 'should allow empty rack env in rspec tests' do
    env = {} # the rack env is empty when running rails/rspec tests
    Raven.rack_context(env)
    Raven.capture_exception(build_exception)
  end

  it 'should bind request context' do
    Raven::Context.current.rack_env = nil

    app = lambda do |env|
      expect(Raven::Context.current.rack_env).to eq(env)

      ['response', {}, env]
    end
    stack = Raven::Rack.new(app)

    env = { :foo => :bar }

    stack.call(env)
  end

  it 'transforms headers to conform with the interface' do
    env = { "SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_FOO" => "BAR", "HTTP_VERSION" => "HTTP/1.1" }

    interface = Raven::HttpInterface.new
    interface.from_rack(env)

    expect(interface.headers["Foo"]).to eq("BAR")
    expect(interface.headers["Version"]).to be_nil
  end

  it 'does not ignore version headers which do not match SERVER_PROTOCOL' do
    env = { "SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/2.0" }

    interface = Raven::HttpInterface.new
    interface.from_rack(env)

    expect(interface.headers["Version"]).to eq("HTTP/2.0")
  end

  it 'does not fail if an object in the env cannot be cast to string' do
    obj = Class.new do
      def to_s
        raise 'Could not stringify object!'
      end
    end.new

    env = { "HTTP_FOO" => "BAR", "rails_object" => obj }
    interface = Raven::HttpInterface.new

    expect { interface.from_rack(env) }.to_not raise_error
  end

  it 'should pass rack/lint' do
    env = Rack::MockRequest.env_for("/test")

    app = proc do
      [200, { 'Content-Type' => 'text/plain' }, ['OK']]
    end

    stack = Raven::Rack.new(Rack::Lint.new(app))
    expect { stack.call(env) }.to_not raise_error
  end
end
