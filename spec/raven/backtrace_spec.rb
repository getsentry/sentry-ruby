require 'spec_helper'

RSpec.describe Raven::Backtrace do
  before(:each) do
    @backtrace = Raven::Backtrace.parse(Thread.current.backtrace)
  end

  it "#lines" do
    expect(@backtrace.lines.first).to be_a(Raven::Backtrace::Line)
  end

  it "#inspect" do
    expect(@backtrace.inspect).to match(/Backtrace: .*>$/)
  end

  it "#to_s" do
    expect(@backtrace.to_s).to match(/backtrace_spec.rb:5/)
  end

  it "==" do
    @backtrace2 = Raven::Backtrace.new(@backtrace.lines)
    expect(@backtrace).to be == @backtrace2
  end
end
