# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::Metric do
  describe '#add' do
    it 'raises not implemented error' do
      expect { subject.add(1) }.to raise_error(NotImplementedError)
    end
  end

  describe '#serialize' do
    it 'raises not implemented error' do
      expect { subject.serialize }.to raise_error(NotImplementedError)
    end
  end

  describe '#weight' do
    it 'raises not implemented error' do
      expect { subject.weight }.to raise_error(NotImplementedError)
    end
  end
end
