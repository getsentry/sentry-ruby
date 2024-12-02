# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::Timing do
  let(:fake_time) { Time.new(2024, 1, 2, 3, 4, 5) }
  before { allow(Time).to receive(:now).and_return(fake_time) }

  describe '.nanosecond' do
    it 'returns nanoseconds' do
      expect(described_class.nanosecond).to eq(fake_time.to_i * 10 ** 9)
    end
  end

  describe '.microsecond' do
    it 'returns microseconds' do
      expect(described_class.microsecond).to eq(fake_time.to_i * 10 ** 6)
    end
  end

  describe '.millisecond' do
    it 'returns milliseconds' do
      expect(described_class.millisecond).to eq(fake_time.to_i * 10 ** 3)
    end
  end

  describe '.second' do
    it 'returns seconds' do
      expect(described_class.second).to eq(fake_time.to_i)
    end
  end

  describe '.minute' do
    it 'returns minutes' do
      expect(described_class.minute).to eq(fake_time.to_i / 60.0)
    end
  end

  describe '.hour' do
    it 'returns hours' do
      expect(described_class.hour).to eq(fake_time.to_i / 3600.0)
    end
  end

  describe '.day' do
    it 'returns days' do
      expect(described_class.day).to eq(fake_time.to_i / (3600.0 * 24.0))
    end
  end

  describe '.week' do
    it 'returns weeks' do
      expect(described_class.week).to eq(fake_time.to_i / (3600.0 * 24.0 * 7.0))
    end
  end
end
