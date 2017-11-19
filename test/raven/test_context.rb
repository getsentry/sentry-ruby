require 'test_helper'

class RavenContextTest < Raven::Test
  it "manages thread context" do
    thread_ctx = Raven::Context.current
    assert_instance_of Raven::Context, thread_ctx
    assert_equal thread_ctx, Raven::Context.current

    Raven::Context.clear!
    refute_equal thread_ctx, Raven::Context.current
  end

  it "has a new context for each thread" do
    thread_ctx = Raven::Context.current
    t = Thread.new { Thread.current[:context] = Raven::Context.current }
    t.join

    refute_equal thread_ctx, t[:context]
  end

  it "merges extra context with server" do
    @ctx = Raven::Context.new

    assert @ctx.extra.keys.include?(:server)

    @ctx.extra[:my_key] = :my_val

    assert_equal :my_val, @ctx.extra[:my_key]
    assert @ctx.extra.keys.include?(:server)
  end
end

class RavenOSContextTest < Raven::ThreadUnsafeTest
  it "has os context" do
    ctx = Raven::Context.new
    sys = Minitest::Mock.new
    sys.expect :command, "foo", ["uname -s"]
    sys.expect :command, "foo", ["uname -v"]
    sys.expect :command, "foo", ["uname -r"]
    sys.expect :command, "foo", ["uname -a"]

    Raven::Context.stub(:sys, sys) do
      ctx.extra
    end

    sys.verify
  end

  it "has runtime context" do
    ctx = Raven::Context.new

    assert_equal RUBY_ENGINE, ctx.extra[:server][:runtime][:name]
    assert_equal RUBY_DESCRIPTION, ctx.extra[:server][:runtime][:version]
  end
end
