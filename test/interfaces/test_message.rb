require_relative '../helper'

class TestMessageInterface < Raven::MessageInterface
end

class MessageInterfaceTest < Minitest::Spec
  it "is registered" do
    assert_includes Raven::Interface.registered, :message
  end

  it "supports invalid format string message when params is empty" do
    int = TestMessageInterface.new(:message => "test '%'")
    assert_equal "test '%'", int.unformatted_message
  end

  it "supports invalid format string message when params is not defined" do
    int = TestMessageInterface.new(:params => nil, :message => "test '%'")
    assert_equal "test '%'", int.unformatted_message
  end
end
