require "spec_helper"
require "rack/timeout/base"
require "raven/integrations/rack_timeout"

RSpec.describe "Rack timeout" do
  it "prints deprecation warning when requiring with dasherized filename" do
    expect do
      require "raven/integrations/rack-timeout"
    end.to output(
      "[Deprecation Warning] Dasherized filename \"raven/integrations/rack-timeout\" is deprecated and will be removed in 4.0; use \"raven/integrations/rack_timeout\" instead\n" # rubocop:disable Style/LineLength
    ).to_stderr
  end
  it "should have a raven_context method defined" do
    exc = Rack::Timeout::RequestTimeoutException.new("REQUEST_URI" => "This is a URI")

    expect(exc.raven_context[:fingerprint]).to eq(["{{ default }}", "This is a URI"])
  end

  it "should return an empty context if env is missing" do
    exception = Object.new
    exception.extend(RackTimeoutExtensions)

    expect(exception.raven_context).to eq({})
  end
end
