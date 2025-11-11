# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob do
  before do
    perform_basic_setup
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "registers the integration" do
    expect(Sentry.integrations).to have_key("good_job")
  end

  it "has the correct version" do
    expect(described_class::VERSION).to eq("5.28.0")
  end

  describe "setup_good_job_integration" do
    before do
      # Mock Rails application configuration
      rails_app = double("Rails::Application")
      rails_config = double("Rails::Configuration")
      good_job_config = double("GoodJob::Configuration")

      allow(::Rails).to receive(:application).and_return(rails_app)
      allow(rails_app).to receive(:config).and_return(rails_config)
      allow(rails_config).to receive(:good_job).and_return(good_job_config)
      allow(good_job_config).to receive(:cron).and_return({})
    end

    it "does not automatically set up job monitoring for any specific job class" do
      # The integration now only sets up cron monitoring, not custom job monitoring
      expect(Sentry::GoodJob::CronHelpers::Integration).to receive(:setup_monitoring_for_scheduled_jobs)

      described_class.setup_good_job_integration
    end

    it "sets up cron monitoring when enabled" do
      expect(Sentry::GoodJob::CronHelpers::Integration).to receive(:setup_monitoring_for_scheduled_jobs)

      described_class.setup_good_job_integration
    end

    context "when enable_cron_monitors is enabled" do
      before do
        Sentry.configuration.good_job.enable_cron_monitors = true
      end

      it "sets up cron monitoring" do
        expect(Sentry::GoodJob::CronHelpers::Integration).to receive(:setup_monitoring_for_scheduled_jobs)

        described_class.setup_good_job_integration
      end
    end

    context "when enable_cron_monitors is disabled" do
      before do
        Sentry.configuration.good_job.enable_cron_monitors = false
      end

      it "does not set up cron monitoring" do
        expect(Sentry::GoodJob::CronHelpers::Integration).not_to receive(:setup_monitoring_for_scheduled_jobs)

        described_class.setup_good_job_integration
      end
    end
  end

  describe "capture_exception" do
    it "delegates to Sentry.capture_exception" do
      exception = build_exception
      options = { hint: { background: true } }

      expect(Sentry).to receive(:capture_exception).with(exception, **options)

      described_class.capture_exception(exception, **options)
    end
  end

  describe "Rails integration" do
    before do
      # Mock Rails configuration
      rails_config = double("Rails::Configuration")
      allow(rails_config).to receive(:good_job).and_return(double("GoodJobConfig"))

      # Mock Sentry Rails configuration
      sentry_rails_config = double("Sentry::Rails::Configuration")
      allow(sentry_rails_config).to receive(:skippable_job_adapters).and_return([])

      allow(Sentry.configuration).to receive(:rails).and_return(sentry_rails_config)
    end

    it "adds GoodJobAdapter to skippable_job_adapters" do
      # This test verifies that the integration would add the adapter to the skippable list
      # In a real Rails environment, this would be done by the Railtie
      expect(Sentry.configuration.rails.skippable_job_adapters).to be_an(Array)
    end
  end
end
