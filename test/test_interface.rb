require_relative 'helper'

class TestInterface < Raven::Interface
  attr_accessor :foo
end

class InterfaceTest < Minitest::Spec
  it "accepts attributes when initialized" do
    int = TestInterface.new(:foo => :bar)
    assert_equal :bar, int.foo
  end

  it "yields during init" do
    int = TestInterface.new { |i| i.foo = :bar }
    assert_equal :bar, int.foo
  end

  it "registers its inheritance" do
    assert_includes Raven::Interface.registered, :test
  end

  it "converts instance variables to a hash" do
    int = TestInterface.new(:foo => :bar)
    assert_equal({ :foo => :bar }, int.to_hash)
  end
end
