# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::GaugeMetric do
  subject { described_class.new(0) }
  before { 9.times { |i| subject.add(i + 1) } }

  describe '#add' do
    it 'appends float value to array' do
      subject.add(11)
      expect(subject.last).to eq(11.0)
      expect(subject.min).to eq(0.0)
      expect(subject.max).to eq(11.0)
      expect(subject.sum).to eq(56.0)
      expect(subject.count).to eq(11)
    end
  end

  describe '#serialize' do
    it 'returns array of statistics' do
      expect(subject.serialize).to eq([9.0, 0.0, 9.0, 45.0, 10])
    end
  end

  describe '#weight' do
    it 'returns fixed value of 5' do
      expect(subject.weight).to eq(5)
    end
  end
end
