require 'spec_helper'
require 'raven/cli'

describe "CLI tests" do
  it "posting an exception" do
    expect(Raven::CLI.test(Raven.configuration.server, true, Raven.configuration)).to be_a(Raven::Event)
  end
end
