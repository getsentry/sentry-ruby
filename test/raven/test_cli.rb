require 'test_helper'
require 'raven/cli'

class RavenCLITest < Raven::Test
  it "posts an exception" do
    event = Raven::CLI.test(Raven.configuration.server, true, Raven.configuration)
    assert_instance_of Raven::Event, event
    assert_equal "ZeroDivisionError: divided by 0", event.message
  end
end
