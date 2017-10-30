require 'test_helper'

class StacktraceInterfaceTest < Raven::ThreadUnsafeTest
  it "should convert pathnames to strings" do
    frame = Raven::StacktraceInterface::Frame.new
    $LOAD_PATH.unshift Pathname.pwd # Oh no, a Pathname in the $LOAD_PATH!
    frame.abs_path = __FILE__
    assert_match(/test_stack_trace.rb/, frame.filename)
    $LOAD_PATH.shift
  end
end
