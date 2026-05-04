# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Yabeda::Adapter do
  subject(:adapter) { described_class.new }

  let(:tags) { { region: "us-east", service: "api" } }

  def build_metric(type, name:, group: nil, unit: nil)
    metric = double(type.to_s)
    allow(metric).to receive(:name).and_return(name)
    allow(metric).to receive(:group).and_return(group)
    allow(metric).to receive(:unit).and_return(unit)
    metric
  end

  describe "metric name construction" do
    it "combines group and name with a dot" do
      perform_basic_setup

      counter = build_metric(:counter, name: :orders_created, group: :myapp)
      expect(Sentry.metrics).to receive(:count).with("myapp.orders_created", value: 1, attributes: nil)

      adapter.perform_counter_increment!(counter, {}, 1)
    end

    it "uses just the name when group is nil" do
      perform_basic_setup

      counter = build_metric(:counter, name: :total_requests)
      expect(Sentry.metrics).to receive(:count).with("total_requests", value: 1, attributes: nil)

      adapter.perform_counter_increment!(counter, {}, 1)
    end
  end

  describe "#perform_counter_increment!" do
    it "calls Sentry.metrics.count with correct arguments" do
      perform_basic_setup

      counter = build_metric(:counter, name: :requests, group: :rails)
      expect(Sentry.metrics).to receive(:count).with(
        "rails.requests",
        value: 5,
        attributes: tags
      )

      adapter.perform_counter_increment!(counter, tags, 5)
    end

    it "passes nil attributes when tags are empty" do
      perform_basic_setup

      counter = build_metric(:counter, name: :requests, group: :rails)
      expect(Sentry.metrics).to receive(:count).with(
        "rails.requests",
        value: 1,
        attributes: nil
      )

      adapter.perform_counter_increment!(counter, {}, 1)
    end
  end

  describe "#perform_gauge_set!" do
    it "calls Sentry.metrics.gauge with correct arguments" do
      perform_basic_setup

      gauge = build_metric(:gauge, name: :queue_depth, group: :sidekiq)
      expect(Sentry.metrics).to receive(:gauge).with(
        "sidekiq.queue_depth",
        42,
        unit: nil,
        attributes: tags
      )

      adapter.perform_gauge_set!(gauge, tags, 42)
    end

    it "passes unit when available" do
      perform_basic_setup

      gauge = build_metric(:gauge, name: :memory_usage, group: :process, unit: :bytes)
      expect(Sentry.metrics).to receive(:gauge).with(
        "process.memory_usage",
        1024,
        unit: "bytes",
        attributes: nil
      )

      adapter.perform_gauge_set!(gauge, {}, 1024)
    end
  end

  describe "#perform_histogram_measure!" do
    it "calls Sentry.metrics.distribution with correct arguments" do
      perform_basic_setup

      histogram = build_metric(:histogram, name: :request_duration, group: :rails, unit: :milliseconds)
      expect(Sentry.metrics).to receive(:distribution).with(
        "rails.request_duration",
        150.5,
        unit: "milliseconds",
        attributes: tags
      )

      adapter.perform_histogram_measure!(histogram, tags, 150.5)
    end
  end

  describe "#perform_summary_observe!" do
    it "calls Sentry.metrics.distribution with correct arguments" do
      perform_basic_setup

      summary = build_metric(:summary, name: :response_size, group: :http, unit: :bytes)
      expect(Sentry.metrics).to receive(:distribution).with(
        "http.response_size",
        2048,
        unit: "bytes",
        attributes: tags
      )

      adapter.perform_summary_observe!(summary, tags, 2048)
    end
  end

  describe "registration methods (no-ops)" do
    it "accepts register_counter! without error" do
      expect { adapter.register_counter!(double) }.not_to raise_error
    end

    it "accepts register_gauge! without error" do
      expect { adapter.register_gauge!(double) }.not_to raise_error
    end

    it "accepts register_histogram! without error" do
      expect { adapter.register_histogram!(double) }.not_to raise_error
    end

    it "accepts register_summary! without error" do
      expect { adapter.register_summary!(double) }.not_to raise_error
    end
  end

  describe "guard conditions" do
    it "does not emit metrics when Sentry is not initialized" do
      expect(Sentry.metrics).not_to receive(:count)

      counter = build_metric(:counter, name: :requests, group: :rails)
      adapter.perform_counter_increment!(counter, {}, 1)
    end

    it "does not emit metrics when metrics are disabled" do
      perform_basic_setup do |config|
        config.enable_metrics = false
      end

      expect(Sentry.metrics).not_to receive(:count)

      counter = build_metric(:counter, name: :requests, group: :rails)
      adapter.perform_counter_increment!(counter, {}, 1)
    end

    it "does not emit gauge when metrics are disabled" do
      perform_basic_setup { |c| c.enable_metrics = false }

      expect(Sentry.metrics).not_to receive(:gauge)

      gauge = build_metric(:gauge, name: :queue_depth)
      adapter.perform_gauge_set!(gauge, {}, 1)
    end

    it "does not emit histogram when metrics are disabled" do
      perform_basic_setup { |c| c.enable_metrics = false }

      expect(Sentry.metrics).not_to receive(:distribution)

      histogram = build_metric(:histogram, name: :duration)
      adapter.perform_histogram_measure!(histogram, {}, 1.0)
    end

    it "does not emit summary when metrics are disabled" do
      perform_basic_setup { |c| c.enable_metrics = false }

      expect(Sentry.metrics).not_to receive(:distribution)

      summary = build_metric(:summary, name: :response_size)
      adapter.perform_summary_observe!(summary, {}, 100)
    end
  end

  describe "tag passthrough" do
    it "passes all tags as Sentry attributes" do
      perform_basic_setup

      complex_tags = { controller: "orders", action: "create", region: "eu-west", status: 200 }
      counter = build_metric(:counter, name: :requests, group: :rails)

      expect(Sentry.metrics).to receive(:count).with(
        "rails.requests",
        value: 1,
        attributes: complex_tags
      )

      adapter.perform_counter_increment!(counter, complex_tags, 1)
    end
  end
end
