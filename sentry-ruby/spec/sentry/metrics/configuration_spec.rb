# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::Configuration do
  describe '#before_emit=' do
    it 'raises error when setting before_emit to anything other than callable or nil' do
      subject.before_emit = -> { }
      subject.before_emit = nil
      expect { subject.before_emit = true }.to raise_error(ArgumentError, 'metrics.before_emit must be callable (or nil to disable)')
    end
  end
end
