# frozen_string_literal: true

RSpec.describe Sentry::Cron::Slug do
  describe ".from" do
    it "replaces runs of other characters with a dash" do
      expect(described_class.from("Reports::Daily Sync!")).to eq("reports-daily-sync")
    end

    it "strips leading and trailing dashes" do
      expect(described_class.from("--Hourly Sync!-")).to eq("hourly-sync")
    end

    it "truncates to the max slug length without a trailing dash" do
      expect(described_class.from("#{"a" * 48}--b")).to eq("a" * 48)
    end

    it "returns nil when nothing usable is left" do
      expect(described_class.from("!!!")).to be_nil
    end
  end
end
