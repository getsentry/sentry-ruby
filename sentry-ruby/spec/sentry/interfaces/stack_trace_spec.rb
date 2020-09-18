require 'spec_helper'

RSpec.describe Sentry::StacktraceInterface::Frame do
  it "should convert pathnames to strings" do
    frame = Sentry::StacktraceInterface::Frame.new
    $LOAD_PATH.unshift Pathname.pwd # Oh no, a Pathname in the $LOAD_PATH!
    frame.abs_path = __FILE__
    expect(frame.filename).to match(/stack_trace_spec.rb/)
    $LOAD_PATH.shift
  end
end
