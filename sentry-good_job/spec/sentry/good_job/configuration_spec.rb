# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::Configuration do
  before do
    perform_basic_setup
  end

  let(:config) { Sentry.configuration.good_job }

  describe "default values" do
    it "sets default values correctly" do
      expect(config.report_after_job_retries).to eq(false)
      expect(config.report_only_dead_jobs).to eq(false)
      expect(config.propagate_traces).to eq(true)
      expect(config.include_job_arguments).to eq(false)
      expect(config.auto_setup_cron_monitoring).to eq(true)
      expect(config.logging_enabled).to eq(false)
      expect(config.logger).to be_nil
    end
  end

  describe "IGNORE_DEFAULT" do
    it "includes expected exceptions" do
      expect(Sentry::GoodJob::IGNORE_DEFAULT).to include(
        "ActiveJob::DeserializationError",
        "ActiveJob::SerializationError"
      )
    end
  end

  describe "configuration attributes" do
    it "allows setting report_after_job_retries" do
      config.report_after_job_retries = true
      expect(config.report_after_job_retries).to eq(true)
    end

    it "allows setting report_only_dead_jobs" do
      config.report_only_dead_jobs = true
      expect(config.report_only_dead_jobs).to eq(true)
    end

    it "allows setting propagate_traces" do
      config.propagate_traces = false
      expect(config.propagate_traces).to eq(false)
    end

    it "allows setting include_job_arguments" do
      config.include_job_arguments = true
      expect(config.include_job_arguments).to eq(true)
    end

    it "allows setting auto_setup_cron_monitoring" do
      config.auto_setup_cron_monitoring = false
      expect(config.auto_setup_cron_monitoring).to eq(false)
    end

    it "allows setting logging_enabled" do
      config.logging_enabled = true
      expect(config.logging_enabled).to eq(true)
    end

    it "allows setting logger" do
      logger = double("Logger")
      config.logger = logger
      expect(config.logger).to eq(logger)
    end
  end
end
