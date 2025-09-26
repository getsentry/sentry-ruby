# frozen_string_literal: true

RSpec.describe Sentry::Metrics::Configuration do
  let(:string_io) { StringIO.new }
  let(:sdk_logger) { Logger.new(string_io) }

  let(:subject) { described_class.new(sdk_logger) }

  describe '#enabled=' do
    it 'logs deprecation warning' do
      subject.enabled = true

      expect(string_io.string).to include(
        "WARN -- sentry: `config.metrics` is now deprecated and will be removed in the next major."
      )
    end
  end

  describe '#before_emit=' do
    it 'raises error when setting before_emit to anything other than callable or nil' do
      subject.before_emit = -> { }
      subject.before_emit = nil
      expect { subject.before_emit = true }.to raise_error(ArgumentError, 'metrics.before_emit must be callable (or nil to disable)')
    end
  end
end
