require 'spec_helper'

describe Raven::Backtrace do
  before(:each) do
    @backtrace = Raven::Backtrace.parse(Thread.current.backtrace)
  end

  it "#inspect" do
    expect(@backtrace.inspect).to match(/Backtrace: .*>$/)
  end
end
