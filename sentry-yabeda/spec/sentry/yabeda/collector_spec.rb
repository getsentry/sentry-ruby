# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Yabeda::Collector do
  before { perform_basic_setup }

  after { Sentry::Yabeda.stop_collector! }

  describe "#run" do
    it "calls Yabeda.collect!" do
      collector = described_class.new(interval: 999)

      expect(::Yabeda).to receive(:collect!)
      collector.run
    end

    it "does not raise when Yabeda.collect! fails" do
      collector = described_class.new(interval: 999)

      allow(::Yabeda).to receive(:collect!).and_raise(RuntimeError, "boom")
      expect { collector.run }.not_to raise_error
    end
  end

  describe ".start_collector! / .stop_collector!" do
    it "creates and stops a collector" do
      Sentry::Yabeda.start_collector!(interval: 999)
      expect(Sentry::Yabeda.collector).to be_a(described_class)

      Sentry::Yabeda.stop_collector!
      expect(Sentry::Yabeda.collector).to be_nil
    end

    it "replaces the collector when called again" do
      Sentry::Yabeda.start_collector!(interval: 999)
      first = Sentry::Yabeda.collector

      Sentry::Yabeda.start_collector!(interval: 999)
      second = Sentry::Yabeda.collector

      expect(second).not_to equal(first)
    end

    it "raises when called before Sentry.init" do
      reset_sentry_globals!

      expect { Sentry::Yabeda.start_collector! }.to raise_error(ArgumentError, /Sentry\.init/)
    end
  end
end
