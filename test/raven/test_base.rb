require 'test_helper'

class RavenTest < Raven::Test
  # sys_command
  it "sends a system command" do
    output = Raven.sys_command("echo 'Sentry'")
    assert_equal "Sentry", output
  end

  it "deals with system commands that exit incorrectly" do
    output = Raven.sys_command("ls --fail")
    assert_nil output
  end
end
