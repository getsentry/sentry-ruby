# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics do
  let(:stringio) { StringIO.new }

  before do
    perform_basic_setup do |config|
      config.logger = ::Logger.new(stringio)
    end
  end

  let(:aggregator) { Sentry.metrics_aggregator }
  let(:fake_time) { Time.new(2024, 1, 1, 1, 1, 3) }

  %i[increment distribution set gauge timing distribution].each do |method|
    describe ".#{method}" do
      it 'logs deprecation warning' do
        described_class.send(
          method,
          'foo',
          5.0,
          unit: 'second',
          tags: { fortytwo: 42 },
          timestamp: fake_time
        )

        expect(stringio.string).to include(
          "WARN -- sentry: `Sentry::Metrics` is now deprecated and will be removed in the next major."
        )
      end
    end
  end
end
