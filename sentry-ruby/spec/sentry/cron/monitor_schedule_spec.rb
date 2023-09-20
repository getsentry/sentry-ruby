require 'spec_helper'

RSpec.describe Sentry::Cron::MonitorSchedule::Crontab do
  let(:subject) { described_class.new('5 * * * *') }

  describe '#value' do
    it 'has correct value' do
      expect(subject.value).to eq('5 * * * *')
    end
  end

  describe '#to_hash' do
    it 'has correct attributes' do
      expect(subject.to_hash).to eq({ type: :crontab, value: subject.value })
    end
  end
end

RSpec.describe Sentry::Cron::MonitorSchedule::Interval do
  let(:subject) { described_class.new(5, :minute) }

  describe '#value' do
    it 'has correct value' do
      expect(subject.value).to eq(5)
    end
  end

  describe '#unit' do
    it 'has correct unit' do
      expect(subject.unit).to eq(:minute)
    end
  end

  describe '#to_hash' do
    it 'has correct attributes' do
      expect(subject.to_hash).to eq({ type: :interval, value: subject.value, unit: subject.unit })
    end
  end
end
