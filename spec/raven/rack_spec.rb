require File.expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven::Rack do
  it 'should capture exceptions' do
    exception = build_exception
    env = {}

    Raven::Rack.should_receive(:capture_exception).with(exception, env)

    app = lambda do |e|
      raise exception
    end

    stack = Raven::Rack.new(app)
    expect { stack.call(env) }.to raise_error
  end

  it 'should capture rack.exception' do
    exception = build_exception
    env = {}

    Raven::Rack.should_receive(:capture_exception).with(exception, env)

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

    Raven::Rack.should_receive(:capture_exception).with(exception, env)

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

    Raven::Context.current.tags.should eq({})
  end

  it 'should allow empty rack env in rspec tests' do
    env = {} # the rack env is empty when running rails/rspec tests
    Raven.rack_context(env)
    expect { Raven.capture_exception(build_exception()) }.not_to raise_error
  end

  it 'should bind request context' do
    Raven::Context.current.rack_env = nil

    app = lambda do |env|
      Raven::Context.current.rack_env.should eq(env)

      ['response', {}, env]
    end
    stack = Raven::Rack.new(app)

    env = { :foo => :bar }

    stack.call(env)
  end

end
