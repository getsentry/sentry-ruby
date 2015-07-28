require 'spec_helper'
require 'raven/integrations/rack'

describe Raven::Rack do
  it 'should capture exceptions' do
    exception = build_exception
    env = {}

    expect(Raven::Rack).to receive(:capture_exception).with(exception, env)

    app = lambda { |_e| raise exception }

    stack = Raven::Rack.new(app)
    expect { stack.call(env) }.to raise_error
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

    app = lambda { |env| ['response', {}, env] }
    stack = Raven::Rack.new(app)

    stack.call({})

    expect(Raven::Context.current.tags).to eq({})
  end

  it 'should allow empty rack env in rspec tests' do
    env = {} # the rack env is empty when running rails/rspec tests
    Raven.rack_context(env)
    expect { Raven.capture_exception(build_exception) }.not_to raise_error
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

  it 'should pass rack/lint' do
    env = Rack::MockRequest.env_for("/test")

    app = lambda do |e|
      [200, {'Content-Type' => 'text/plain'}, ['OK']]
    end

    stack = Raven::Rack.new(Rack::Lint.new(app))
    expect { stack.call(env) }.to_not raise_error(Rack::Lint::LintError)
  end

end
