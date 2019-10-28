require 'spec_helper'
require 'raven/cli'

RSpec.describe "CLI tests" do
  it "posting an exception" do
    event = Raven::CLI.test(Raven.configuration.server, true, Raven.configuration)
    expect(event).to be_a(Raven::Event)
    hash = event.to_hash
    expect(hash[:exception][:values][0][:type]).to eq("ZeroDivisionError")
    expect(hash[:exception][:values][0][:value]).to eq("divided by 0")
  end
end
