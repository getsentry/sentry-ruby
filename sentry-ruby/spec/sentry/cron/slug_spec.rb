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

  describe ".from_class_name" do
    it "defaults to legacy mashed formatting" do
      expect(described_class.from_class_name("HappyWorkerWithCron"))
        .to eq("happyworkerwithcron")
    end

    it "underscores CamelCase and keeps :: as -" do
      expect(described_class.from_class_name("HappyWorkerWithCron", format: :underscore))
        .to eq("happy_worker_with_cron")
    end

    it "legacy-truncates from the start without hashing" do
      name = "VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job"
      expect(described_class.from_class_name(name, format: :legacy))
        .to eq("ongoutermodule-veryveryveryverylonginnermodule-job")
    end

    it "hash-truncates long underscore slugs and stays within max length" do
      name = "VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job"
      slug = described_class.from_class_name(name, format: :underscore)

      expect(slug.length).to be <= Sentry::Cron::MonitorCheckIns::MAX_SLUG_LENGTH
      expect(slug).to eq("675905e0c9_very_very_very_long_inner_module-job")
    end
  end
end
