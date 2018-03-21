require 'test_helper'
require "raven/integrations/rack-timeout"

class RavenRackTimeoutTest < Raven::Test
  it "should have a raven_context method defined" do
    exc = Rack::Timeout::RequestTimeoutException.new("REQUEST_URI" => "This is a URI")
    assert_equal ["{{ default }}", "This is a URI"], exc.raven_context[:fingerprint]
  end
end
