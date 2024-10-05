# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::CounterMetric do
  subject { described_class.new(1) }
  before { subject.add(2) }

  describe '#add' do
    it 'adds float value' do
      subject.add(3.0)
      expect(subject.value).to eq(6.0)
    end
  end

  describe '#serialize' do
    it 'returns value in array' do
      expect(subject.serialize).to eq([3.0])
    end
  end

  describe '#weight' do
    it 'returns fixed value of 1' do
      expect(subject.weight).to eq(1)
    end
  end
end
