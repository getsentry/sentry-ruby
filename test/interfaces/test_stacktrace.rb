require_relative '../helper'

class StacktraceInterfaceTest < Minitest::Spec
  it "is registered" do
    assert_includes Raven::Interface.registered, :stacktrace
  end

  it "can be created via a backtrace" do
    int = Raven::StacktraceInterface.from_backtrace(backtrace_fixture, linecache_fixture, 3)
    assert int.frames.first.is_a?(Raven::StacktraceInterface::Frame)
    assert_match "1 / 0", int.frames.last.context_line
  end

  describe "frames created via backtrace line" do
    before do
      @frame = Raven::StacktraceInterface::Frame.from_backtrace_line(
        Raven::Backtrace.parse(backtrace_fixture).lines.first,
        linecache_fixture,
        1
      )
    end

    it "sets some attributes" do
      assert_match "raven-ruby/test/helper.rb", @frame.abs_path
      assert_equal "/", @frame.function
      assert_equal 10, @frame.lineno
      refute @frame.in_app
      assert_nil @frame.module
      assert_match "raven-ruby/test/helper.rb", @frame.filename
    end

    it "sets context" do
      assert_equal ["  def build_exception\n"], @frame.pre_context
      assert_equal "    1 / 0\n", @frame.context_line
      assert_equal ["  rescue ZeroDivisionError => exception\n"], @frame.post_context
    end
    
    it "converts to hash" do
      assert @frame.to_hash.is_a?(Hash)
    end
  end

  private

  def backtrace_fixture
    build_exception.backtrace
  end

  def linecache_fixture
    Raven::LineCache.new
  end
end
