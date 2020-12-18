return unless defined?(Rack)

require "spec_helper"

RSpec.describe Sentry::Rack::Tracing, rack: true do
  it "returns friendly message when this class is initialized" do
    expect do
      described_class.new({})
    end.to raise_error(Sentry::Error)
  end
end

RSpec.describe Sentry::Rack::CaptureException do
  it "returns friendly message when this class is initialized" do
    expect do
      described_class.new({})
    end.to raise_error(Sentry::Error)
  end
end
