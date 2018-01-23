require "spec_helper"
require "rack/timeout/base"
require "raven/integrations/rack-timeout"

RSpec.describe "Rack timeout" do
  it "should have a raven_context method defined" do
    exc = Rack::Timeout::RequestTimeoutException.new("REQUEST_URI" => "This is a URI")

    expect(exc.raven_context[:fingerprint]).to eq(["{{ default }}", "This is a URI"])
  end
end
