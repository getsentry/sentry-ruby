require 'spec_helper'

RSpec.describe Sentry::Cron::MonitorConfig do
  describe '.from_crontab' do
    it 'has correct attributes' do
      subject = described_class.from_crontab(
        '5 * * * *',
        checkin_margin: 10,
        max_runtime: 30,
        timezone: 'Europe/Vienna'
      )

      expect(subject.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
      expect(subject.schedule.value).to eq('5 * * * *')
      expect(subject.checkin_margin).to eq(10)
      expect(subject.max_runtime).to eq(30)
      expect(subject.timezone).to eq('Europe/Vienna')
    end
  end

  describe '.from_interval' do
    it 'returns nil without valid unit' do
      expect(described_class.from_interval(5, :bla)).to eq(nil)
    end

    it 'has correct attributes' do
      subject = described_class.from_interval(
        5,
        :hour,
        checkin_margin: 10,
        max_runtime: 30,
        timezone: 'Europe/Vienna'
      )

      expect(subject.schedule).to be_a(Sentry::Cron::MonitorSchedule::Interval)
      expect(subject.schedule.value).to eq(5)
      expect(subject.schedule.unit).to eq(:hour)
      expect(subject.checkin_margin).to eq(10)
      expect(subject.max_runtime).to eq(30)
      expect(subject.timezone).to eq('Europe/Vienna')
    end
  end

  describe '#to_hash' do
    it 'returns hash with correct attributes for crontab' do
      subject = described_class.from_crontab(
        '5 * * * *',
        checkin_margin: 10,
        max_runtime: 30,
        timezone: 'Europe/Vienna'
      )

      hash = subject.to_hash
      expect(hash).to eq({
        schedule: { type: :crontab, value: '5 * * * *' },
        checkin_margin: 10,
        max_runtime: 30,
        timezone: 'Europe/Vienna'
      })
    end

    it 'returns hash with correct attributes for interval' do
      subject = described_class.from_interval(
        5,
        :hour,
        checkin_margin: 10,
        max_runtime: 30,
        timezone: 'Europe/Vienna'
      )

      hash = subject.to_hash
      expect(hash).to eq({
        schedule: { type: :interval, value: 5, unit: :hour },
        checkin_margin: 10,
        max_runtime: 30,
        timezone: 'Europe/Vienna'
      })
    end
  end
end
