# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::DistributionMetric do
  subject { described_class.new(1) }
  before { subject.add(2) }

  describe '#add' do
    it 'appends float value to array' do
      subject.add(3.0)
      expect(subject.value).to eq([1.0, 2.0, 3.0])
    end
  end

  describe '#serialize' do
    it 'returns whole array' do
      expect(subject.serialize).to eq([1.0, 2.0])
    end
  end

  describe '#weight' do
    it 'returns length of array' do
      expect(subject.weight).to eq(2)
    end
  end
end
