require "spec_helper"

RSpec.describe Sentry::Rails::Configuration do
  it "adds #rails option to Sentry::Configuration" do
    config = Sentry::Configuration.new

    expect(config.rails).to be_a(described_class)
  end

  it "concats Rails-specific ignore exceptions" do
    config = Sentry::Configuration.new

    expect(config.excluded_exceptions).to include("ActiveRecord::RecordNotFound")
  end

  describe "#report_rescued_exceptions" do
    it "has correct default value" do
      expect(subject.report_rescued_exceptions).to eq(true)
    end
  end
end
