require 'test_helper'

class MessageInterfaceTest < Raven::Test
  it "supports invalid format string message when params is not defined" do
    interface = Raven::MessageInterface.new(:params => nil, :message => "test '%'")
    assert_equal "test '%'", interface.unformatted_message
  end

  it "supports invalid format string message when params is empty" do
    interface = Raven::MessageInterface.new(:message => "test '%'")
    assert_equal "test '%'", interface.unformatted_message
  end
end
