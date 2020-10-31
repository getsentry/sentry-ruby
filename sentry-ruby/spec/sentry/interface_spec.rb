require 'spec_helper'
require 'sentry/interface'

class TestInterface < Sentry::Interface
  attr_accessor :some_attr
end

RSpec.describe Sentry::Interface do
  it "should register an interface when a new class is defined" do
    expect(Sentry::Interface.registered[:test]).to eq(TestInterface)
  end

  it "serializes to a Hash" do
    interface = TestInterface.new
    interface.some_attr = "test"

    expect(interface.to_hash).to eq(:some_attr => "test")
  end
end
