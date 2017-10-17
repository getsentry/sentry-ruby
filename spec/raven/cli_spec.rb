require 'spec_helper'
require 'raven/cli'

RSpec.describe "CLI tests" do
  it "posting an exception" do
    event = Raven::CLI.test(Raven.configuration.server, true, Raven.configuration)
    expect(event).to be_a(Raven::Event)
    expect(event.message).to eq("ZeroDivisionError: divided by 0")
  end
end
