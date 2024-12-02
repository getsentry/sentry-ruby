# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::DelayedJob::Configuration do
  it "adds #delayed_job option to Sentry::Configuration" do
    config = Sentry::Configuration.new

    expect(config.delayed_job).to be_a(described_class)
  end

  describe "#report_after_job_retries" do
    it "has correct default value" do
      expect(subject.report_after_job_retries).to eq(false)
    end
  end
end
