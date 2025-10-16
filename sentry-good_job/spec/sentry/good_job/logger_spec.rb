# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::Logger do
  before do
    perform_basic_setup
  end

  let(:mock_logger) { double("Logger") }

  describe ".enabled?" do
    context "when logging is disabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = false
      end

      it "returns false" do
        expect(described_class.enabled?).to be false
      end
    end

    context "when logging is enabled but no logger is available" do
      before do
        Sentry.configuration.good_job.logging_enabled = true
        Sentry.configuration.good_job.logger = nil
        allow(described_class).to receive(:logger).and_return(nil)
      end

      it "returns false" do
        expect(described_class.enabled?).to be false
      end
    end

    context "when logging is enabled and logger is available" do
      before do
        Sentry.configuration.good_job.logging_enabled = true
        allow(described_class).to receive(:logger).and_return(mock_logger)
      end

      it "returns true" do
        expect(described_class.enabled?).to be true
      end
    end
  end

  describe ".logger" do
    context "when custom logger is configured" do
      before do
        Sentry.configuration.good_job.logger = mock_logger
      end

      it "returns the custom logger" do
        expect(described_class.logger).to eq(mock_logger)
      end
    end

    context "when no custom logger is configured" do
      before do
        Sentry.configuration.good_job.logger = nil
      end

      context "and Rails is available" do
        before do
          stub_const("Rails", double("Rails"))
          allow(Rails).to receive(:respond_to?).with(:logger).and_return(true)
          allow(Rails).to receive(:logger).and_return(mock_logger)
        end

        it "returns Rails.logger" do
          expect(described_class.logger).to eq(mock_logger)
        end
      end

      context "and Rails is not available" do
        before do
          hide_const("Rails")
        end

        it "returns nil" do
          expect(described_class.logger).to be_nil
        end
      end
    end
  end

  describe ".info" do
    context "when logging is enabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = true
        allow(described_class).to receive(:logger).and_return(mock_logger)
      end

      it "logs the message" do
        expect(mock_logger).to receive(:info).with("test message")
        described_class.info("test message")
      end
    end

    context "when logging is disabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = false
      end

      it "does not log the message" do
        expect(mock_logger).not_to receive(:info)
        described_class.info("test message")
      end
    end
  end

  describe ".warn" do
    context "when logging is enabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = true
        allow(described_class).to receive(:logger).and_return(mock_logger)
      end

      it "logs the warning" do
        expect(mock_logger).to receive(:warn).with("test warning")
        described_class.warn("test warning")
      end
    end

    context "when logging is disabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = false
      end

      it "does not log the warning" do
        expect(mock_logger).not_to receive(:warn)
        described_class.warn("test warning")
      end
    end
  end

  describe ".error" do
    context "when logging is enabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = true
        allow(described_class).to receive(:logger).and_return(mock_logger)
      end

      it "logs the error" do
        expect(mock_logger).to receive(:error).with("test error")
        described_class.error("test error")
      end
    end

    context "when logging is disabled" do
      before do
        Sentry.configuration.good_job.logging_enabled = false
      end

      it "does not log the error" do
        expect(mock_logger).not_to receive(:error)
        described_class.error("test error")
      end
    end
  end
end
