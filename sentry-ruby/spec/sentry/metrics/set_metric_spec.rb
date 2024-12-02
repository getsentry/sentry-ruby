# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::SetMetric do
  subject { described_class.new('foo') }

  before do
    2.times { subject.add('foo') }
    2.times { subject.add('bar') }
    2.times { subject.add(42) }
  end

  describe '#add' do
    it 'appends new value to set' do
      subject.add('baz')
      expect(subject.value).to eq(Set['foo', 'bar', 'baz', 42])
    end
  end

  describe '#serialize' do
    it 'returns array of hashed values' do
      expect(subject.serialize).to eq([Zlib.crc32('foo'), Zlib.crc32('bar'), 42])
    end
  end

  describe '#weight' do
    it 'returns length of set' do
      expect(subject.weight).to eq(3)
    end
  end
end
