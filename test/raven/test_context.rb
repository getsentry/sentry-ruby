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

  it "merges extra context with server" do
    context = Raven::Context.new

    assert context.extra.keys.include?(:server)

    context.extra[:my_key] = :my_val

    assert_equal :my_val, context.extra[:my_key]
    assert context.extra.keys.include?(:server)
  end

  it "has runtime context" do
    context = Raven::Context.new

    assert_equal RUBY_ENGINE, context.extra[:server][:runtime][:name]
    assert_equal RUBY_DESCRIPTION, context.extra[:server][:runtime][:version]
  end

  # rack - sets ip ip_address

  # rack truncates data

  # configuration context
  # events override it

  # Raven._context methods
end

class RavenOSContextTest < Raven::ThreadUnsafeTest
  it "has os context" do
    sys = Minitest::Mock.new
    sys.expect :command, "foo", ["uname -s"]
    sys.expect :command, "foo", ["uname -v"]
    sys.expect :command, "foo", ["uname -r"]
    sys.expect :command, "foo", ["uname -a"]

    Raven::System.stub(:new, sys) do
      Raven::Context.new
    end

    sys.verify
  end
end
