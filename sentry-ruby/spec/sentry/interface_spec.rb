require 'spec_helper'
require 'sentry/interface'

class TestInterface < Sentry::Interface
  attr_accessor :some_attr
end

RSpec.describe Sentry::Interface do
  it "serializes to a Hash" do
    interface = TestInterface.new
    interface.some_attr = "test"

    expect(interface.to_hash).to eq(:some_attr => "test")
  end
end
