# frozen_string_literal: true

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

  describe "#tracing_subscribers" do
    class MySubscriber; end

    it "returns the default subscribers" do
      expect(subject.tracing_subscribers.size).to eq(4)
    end

    it "is customizable" do
      subject.tracing_subscribers << MySubscriber
      expect(subject.tracing_subscribers.size).to eq(5)
    end

    it "is replaceable" do
      subject.tracing_subscribers = [MySubscriber]
      expect(subject.tracing_subscribers.size).to eq(1)
    end
  end

  describe "#active_support_logger_subscription_items" do
    it "returns the default active support logger subscription items" do
      expect(subject.active_support_logger_subscription_items.keys.size).to eq(47)
    end

    it "is customizable" do
      subject.active_support_logger_subscription_items["foo"] = %i[bar]
      expect(subject.active_support_logger_subscription_items.keys.size).to eq(48)

      subject.active_support_logger_subscription_items["process_action.action_controller"] << :bar
      expect(subject.active_support_logger_subscription_items["process_action.action_controller"]).to include(:bar)
    end

    it "is replaceable" do
      subject.active_support_logger_subscription_items = { "foo" => %i[bar] }

      expect(subject.active_support_logger_subscription_items.keys.size).to eq(1)
      expect(subject.active_support_logger_subscription_items["foo"]).to include(:bar)
    end
  end

  describe "#active_job_report_on_retry_error" do
    it "has correct default value" do
      expect(subject.active_job_report_on_retry_error).to be(false)
    end
  end

  describe "#structured_logging" do
    let(:config) { Sentry.configuration.rails }

    it "allows enabling by setting to true" do
      make_basic_app do |config|
        config.rails.structured_logging = true
      end

      expect(config.structured_logging.enabled).to be(true)
      expect(config.structured_logging.subscribers).to be_a(Hash)
    end

    it "allows disabling by setting to false" do
      make_basic_app do |config|
        config.rails.structured_logging = false
      end

      expect(config.structured_logging.enabled).to be(false)
      expect(config.structured_logging.subscribers).to be_a(Hash)
    end

    it "allows customizing subscribers" do
      class TestSubscriber; end

      make_basic_app do |config|
        config.rails.structured_logging = true
        config.rails.structured_logging.subscribers = { action_controller: TestSubscriber }
      end

      expect(config.structured_logging.subscribers.keys).to eql([:action_controller])
      expect(config.structured_logging.subscribers[:action_controller]).to eq(TestSubscriber)
    end
  end
end
