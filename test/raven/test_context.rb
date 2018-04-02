require 'test_helper'

class RavenContextTest < Raven::Test
  # user, tags extra and rack work in the clear case

  it "also has accessors specific to the context type" do
    context = Raven::Context.new

    context.user = { :foo => :bar }
    context.extra = { :foo => :bar }
    context.tags = { :foo => :bar }

    assert_equal :bar, context.extra[:foo]
    assert_equal :bar, context.user[:foo]
    assert_equal :bar, context.tags[:foo]
  end

  it "has accessors which are non-destructive (merge!)" do
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

  # rack - sets ip ip_address

  # rack truncates data

  # configuration context
  # events override it

  # Raven._context methods
end

# Context Collector
