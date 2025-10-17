# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::Configuration do
  before do
    perform_basic_setup
  end

  let(:config) { Sentry.configuration.good_job }

  describe "default values" do
    it "sets default values correctly" do
      expect(config.enable_cron_monitors).to eq(true)
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
    # Removed configuration options that are now handled by sentry-rails:
    # - report_after_job_retries (use sentry-rails active_job_report_on_retry_error)
    # - report_only_discarded_jobs (handled by ActiveJob retry/discard logic)
    # - propagate_traces (handled by sentry-rails)
    # - include_job_arguments (use sentry-rails send_default_pii)

    it "allows setting enable_cron_monitors" do
      config.enable_cron_monitors = false
      expect(config.enable_cron_monitors).to eq(false)
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
