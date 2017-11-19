require 'test_helper'

class RavenBacktraceTest < Raven::Test
  def setup
    @backtrace = Raven::Backtrace.parse(Thread.current.backtrace)
  end

  it "has lines" do
    assert_instance_of Raven::Backtrace::Line, @backtrace.lines.first
  end

  it "has lines in a particular order" do
    assert_equal Dir.pwd + "/test/raven/test_backtrace.rb", @backtrace.lines.last.file
  end

  it "#inspect" do
    assert_match(/Backtrace: .*>$/, @backtrace.inspect)
  end

  it "#to_s" do
    assert_match(/test_backtrace.rb:/, @backtrace.to_s)
  end

  it "==" do
    @backtrace2 = Raven::Backtrace.new(@backtrace.lines)
    assert_equal @backtrace, @backtrace2
  end
end
