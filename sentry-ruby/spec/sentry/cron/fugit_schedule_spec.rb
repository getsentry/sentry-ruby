# frozen_string_literal: true

require "fugit"

RSpec.describe Sentry::Cron::FugitSchedule do
  before { perform_basic_setup }

  def from_cron(cron)
    described_class.from_cron(Fugit.parse_cron(cron))&.to_h
  end

  describe ".from_cron" do
    it "sends the crontab and time zone" do
      expect(from_cron("0 9 * * 1-5 Europe/Vienna")).to eq(
        schedule: { type: :crontab, value: "0 9 * * 1-5" },
        timezone: "Europe/Vienna"
      )
    end

    it "applies the cron config defaults" do
      Sentry.configuration.cron.default_checkin_margin = 5
      Sentry.configuration.cron.default_max_runtime = 30

      expect(from_cron("0 9 * * * UTC")).to include(checkin_margin: 5, max_runtime: 30)
    end

    {
      "*/15 * * * *" => "*/15 * * * *",
      "0 9 * * mon-fri" => "0 9 * * 1-5",
      "0 0 */2 * 1" => "0 0 1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31 * 1",
      "30 0 9 * * *" => "0 9 * * *",
      "@daily" => "0 0 * * *",
      "0 9 L * *" => "0 9 L * *",
      "0 9 1-5,L * *" => "0 9 1-5,L * *",
      "0 9 * * mon#2" => "0 9 * * 1#2",
      "0 9 * * fri#-1" => "0 9 * * 5L",
      "0 9 * * fri#L" => "0 9 * * 5L",
      "0 9 * * mon-wed,mon#2,fri#-1" => "0 9 * * 1-3,1#2,5L",
      "0 9 L * fri" => "0 9 L * 5"
    }.each do |cron, crontab|
      it "sends #{crontab.inspect} for #{cron.inspect}" do
        expect(from_cron("#{cron} UTC")[:schedule]).to eq(type: :crontab, value: crontab)
      end
    end

    ["0 12 -2 * *", "0 12 1,-2 * *", "0 12 * * fri#-2", "0 12 * * mon#2,fri#-2", "0 12 * * mon%2", "0 0 1-7 * mon&", "0 9 L * fri&", "*/10 * * * * *"].each do |cron|
      it "returns nil for #{cron.inspect}" do
        expect(from_cron(cron)).to be_nil
      end
    end

    { "+05:00" => "Etc/GMT-5", "-03:00" => "Etc/GMT+3", "+00:00" => "Etc/UTC", "+0900" => "Etc/GMT-9" }.each do |offset, timezone|
      it "sends #{timezone} for the #{offset} offset" do
        expect(from_cron("0 9 * * * #{offset}")[:timezone]).to eq(timezone)
      end
    end

    it "returns nil for an offset that isn't a whole hour" do
      expect(from_cron("0 9 * * * +05:30")).to be_nil
    end

    it "returns nil when the local time zone is an offset" do
      allow(EtOrbi).to receive(:determine_local_tzone).and_return(EtOrbi.get_tzone("+05:30"))

      expect(from_cron("0 9 * * *")).to be_nil
    end

    it "uses the local time zone when the cron line has none" do
      allow(EtOrbi).to receive(:determine_local_tzone).and_return(TZInfo::Timezone.get("Asia/Tokyo"))

      expect(from_cron("0 9 * * *")[:timezone]).to eq("Asia/Tokyo")
    end

    it "returns nil for non-cron schedules" do
      expect(described_class.from_cron(Fugit.parse("10m"))).to be_nil
    end
  end

  describe ".from_seconds" do
    { 600 => { value: 10, unit: :minute }, 7_200 => { value: 2, unit: :hour }, 86_400 => { value: 1, unit: :day } }.each do |seconds, interval|
      it "sends an interval config for #{seconds}s" do
        expect(described_class.from_seconds(seconds).to_h[:schedule]).to eq(type: :interval, **interval)
      end
    end

    it "returns nil for sub-minute frequencies" do
      expect(described_class.from_seconds(90)).to be_nil
    end
  end
end
