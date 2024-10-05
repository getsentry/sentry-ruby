# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Resque::Configuration do
  it "adds #resque option to Sentry::Configuration" do
    config = Sentry::Configuration.new

    expect(config.resque).to be_a(described_class)
  end

  describe "#report_after_job_retries" do
    it "has correct default value" do
      expect(subject.report_after_job_retries).to eq(false)
    end
  end
end
