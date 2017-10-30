require 'test_helper'

class StacktraceInterfaceTest < Raven::ThreadUnsafeTest
  def setup
    @frame = Raven::StacktraceInterface::Frame.new
    @frame.abs_path = __FILE__
    #@frame.longest_load_path =
  end

  it "should convert pathnames to strings" do
    $LOAD_PATH.unshift Pathname.pwd # Oh no, a Pathname in the $LOAD_PATH!
    assert_match(/test_stack_trace.rb/, @frame.filename)
    $LOAD_PATH.shift
  end

  it "nil if no absolute path" do
    @frame.abs_path = nil
    assert_nil @frame.filename
  end

  it "project root prefix if under the root and an in_app frame" do
    @frame.project_root = Dir.pwd
    @frame.in_app = true

    assert_equal "test/raven/interfaces/test_stack_trace.rb", @frame.filename
  end

  it "project root prefix if we are under it but longest load path doesnt match" do
    @frame.project_root = Dir.pwd
    def @frame.longest_load_path; nil; end
    assert_equal "test/raven/interfaces/test_stack_trace.rb", @frame.filename
  end

  it "otherwise uses longest load path match" do
    @frame.project_root = Dir.pwd
    assert_equal "raven/interfaces/test_stack_trace.rb", @frame.filename
  end

  it "uses longest load path match if not under project root" do
    @frame.project_root = "/some/other"
    assert_equal "raven/interfaces/test_stack_trace.rb", @frame.filename
  end
end
