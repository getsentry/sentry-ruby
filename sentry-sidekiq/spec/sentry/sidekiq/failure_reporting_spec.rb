# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Sidekiq::FailureReporting do
  subject(:reporting) { described_class.new }

  before do
    perform_basic_setup
  end

  def job(**attributes)
    { "class" => "SadWorker", "jid" => "abc123", "queue" => "default" }.merge(attributes.transform_keys(&:to_s))
  end

  context "with config.report_after_job_retries = true" do
    before do
      Sentry.configuration.sidekiq.report_after_job_retries = true
    end

    [false, 0].each do |retry_option|
      it "reports the first failure when retry is #{retry_option}" do
        expect(reporting.report?(job(retry: retry_option))).to be(true)
      end
    end

    if WITH_SIDEKIQ_7
      context "when the passed Sidekiq config sets max_retries" do
        let(:config) { sidekiq_config(max_retries: 3) }

        it "skips failures before the configured retries are exhausted" do
          expect(reporting.report?(job(retry: true, retry_count: 1), config)).to be(false)
        end

        it "reports the failure once the configured retries are exhausted" do
          expect(reporting.report?(job(retry: true, retry_count: 2), config)).to be(true)
        end
      end
    end
  end

  context "with attempt_threshold" do
    [false, 0].each do |retry_option|
      it "reports the first failure when retry is #{retry_option}" do
        expect(reporting.report?(job(retry: retry_option, attempt_threshold: 3))).to be(true)
      end
    end

    if WITH_SIDEKIQ_7
      context "when the passed Sidekiq config sets max_retries below the threshold" do
        let(:config) { sidekiq_config(max_retries: 2) }

        it "skips failures before the final attempt" do
          expect(reporting.report?(job(retry: true, retry_count: 0, attempt_threshold: 5), config)).to be(false)
        end

        it "reports the failure on the final attempt" do
          expect(reporting.report?(job(retry: true, retry_count: 1, attempt_threshold: 5), config)).to be(true)
        end
      end
    end
  end
end
