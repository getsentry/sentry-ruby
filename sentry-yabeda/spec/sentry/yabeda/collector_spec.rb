# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Yabeda::Collector do
  before { perform_basic_setup }

  describe "#run" do
    it "calls Yabeda.collect!" do
      collector = described_class.new(Sentry.configuration, interval: 999)

      expect(::Yabeda).to receive(:collect!)
      collector.run
    end

    it "does not raise when Yabeda.collect! fails" do
      collector = described_class.new(Sentry.configuration, interval: 999)

      allow(::Yabeda).to receive(:collect!).and_raise(RuntimeError, "boom")
      expect { collector.run }.not_to raise_error
    end
  end

  describe "on close" do
    it "performs a final collect before shutting down" do
      expect(::Yabeda).to receive(:collect!)
      Sentry.close
    end

    it "kills the collector and sets it to nil" do
      collector = Sentry::Yabeda.collector
      expect(collector).to receive(:kill).and_call_original
      Sentry.close
      expect(Sentry::Yabeda.collector).to be_nil
    end

    it "does nothing when no collector is running" do
      Sentry::Yabeda.collector = nil
      expect { Sentry.close }.not_to raise_error
    end
  end

  describe "auto-start" do
    it "starts automatically when Sentry is initialized with enable_metrics" do
      expect(Sentry::Yabeda.collector).to be_a(described_class)
    end

    it "does not start when enable_metrics is false" do
      Sentry.close

      Sentry.init do |config|
        config.dsn = DUMMY_DSN
        config.sdk_logger = ::Logger.new(nil)
        config.transport.transport_class = Sentry::DummyTransport
        config.enable_metrics = false
      end

      expect(Sentry::Yabeda.collector).to be_nil
    end

    it "replaces an existing collector on re-initialization via close" do
      first = Sentry::Yabeda.collector

      Sentry.close
      perform_basic_setup

      expect(Sentry::Yabeda.collector).to be_a(described_class)
      expect(Sentry::Yabeda.collector).not_to equal(first)
    end

    it "replaces an existing collector on re-initialization without close" do
      first = Sentry::Yabeda.collector
      expect(first).to receive(:kill).and_call_original

      perform_basic_setup

      expect(Sentry::Yabeda.collector).to be_a(described_class)
      expect(Sentry::Yabeda.collector).not_to equal(first)
    end
  end
end
