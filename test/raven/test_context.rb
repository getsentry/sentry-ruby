require 'test_helper'

class RavenContextTest < Raven::Test
  it "has writers specific to the context type" do
    context = Raven::Context.new

    context.user = { :foo => :bar }
    context.extra = { :foo => :bar }
    context.tags = { :foo => :bar }

    assert_equal :bar, context.extra[:foo]
    assert_equal :bar, context.user[:foo]
    assert_equal :bar, context.tags[:foo]
  end

  it "has writers which are non-destructive (merge!)" do
    context = Raven::Context.new

    context.user = { :baz => :qux }
    context.user = { :foo => :bar }

    assert_equal({ :foo => :bar, :baz => :qux }, context.user)
  end

  it "manages thread context" do
    thread_context = Raven::Context.current
    assert_instance_of Raven::Context, thread_context
    assert_equal thread_context, Raven::Context.current

    Raven::Context.clear!
    refute_equal thread_context, Raven::Context.current
  end

  it "has a new context for each thread" do
    thread_context = Raven::Context.current
    t = Thread.new { Thread.current[:context] = Raven::Context.current }
    t.join

    refute_equal thread_context, t[:context]
  end
end

class RavenContextCollectorTest < Raven::Test
  def setup
    @evt = Raven::Context.new
    @instance = Raven::Context.new
    @config = Raven::Context.new

    @collector = Raven::ContextCollector.new(@evt, @instance, @config)
  end

  it "has a transaction, prefers the event" do
    @instance.transaction.push "MyInstanceTransaction"

    assert_equal "MyInstanceTransaction", @collector.transaction
  end

  it "prefers instance transaction" do
    @evt.transaction.push "MyEventTransaction"
    @instance.transaction.push "MyInstanceTransaction"

    assert_equal "MyEventTransaction", @collector.transaction
  end

  it "prefers instance to config" do
    @instance.user   = { :foo => :bar }
    @config.user     = { :foo => :baz }

    assert_equal :bar, @collector.user[:foo]
  end

  it "prefers event to instance" do
    @evt.user      = { :foo => :bar }
    @instance.user = { :foo => :baz }

    assert_equal :bar, @collector.user[:foo]
  end

  it "full-stack test" do
    @config.tags = {
      'configuration_context_event_key' => 'configuration_value',
      'configuration_context_key' => 'configuration_value',
      'configuration_event_key' => 'configuration_value',
      'configuration_key' => 'configuration_value'
    }

    @instance.tags = {
      'configuration_context_event_key' => 'context_value',
      'configuration_context_key' => 'context_value',
      'context_event_key' => 'context_value',
      'context_key' => 'context_value'
    }

    @evt.tags = {
      'configuration_context_event_key' => 'event_value',
      'configuration_event_key' => 'event_value',
      'context_event_key' => 'event_value',
      'event_key' => 'event_value'
    }

    result = {
      'configuration_context_event_key' => 'event_value',
      'configuration_context_key' => 'context_value',
      'configuration_event_key' => 'event_value',
      'context_event_key' => 'event_value',
      'configuration_key' => 'configuration_value',
      'context_key' => 'context_value',
      'event_key' => 'event_value'
    }
    assert_equal result, @collector.tags
  end
end
