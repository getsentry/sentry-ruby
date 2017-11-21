require 'test_helper'

class TestInterface < Raven::Interface
  attr_accessor :some_attr
end

class RavenInterfaceTest < Raven::Test
  it "can be initialized with some attributes" do
    interface = TestInterface.new(:some_attr => "test")
    assert_equal "test", interface.some_attr
  end

  it "can initialize with a block" do
    interface = TestInterface.new { |int| int.some_attr = "test" }
    assert_equal "test", interface.some_attr
  end

  it "serializes to a Hash" do
    interface = TestInterface.new(:some_attr => "test")
    assert_equal({ :some_attr => "test" }, interface.to_hash)
  end
end
