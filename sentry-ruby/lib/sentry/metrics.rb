# frozen_string_literal: true

require 'sentry/metrics/metric'
require 'sentry/metrics/counter_metric'
require 'sentry/metrics/distribution_metric'
require 'sentry/metrics/gauge_metric'
require 'sentry/metrics/set_metric'
require 'sentry/metrics/aggregator'

module Sentry
  module Metrics
    class << self
      def increment(key, value = 1.0, unit: 'none', tags: {}, timestamp: nil)
        Sentry.metrics_aggregator&.add(:c, key, value, unit: unit, tags: tags, timestamp: timestamp)
      end

      def distribution(key, value, unit: 'none', tags: {}, timestamp: nil)
        Sentry.metrics_aggregator&.add(:d, key, value, unit: unit, tags: tags, timestamp: timestamp)
      end

      def set(key, value, unit: 'none', tags: {}, timestamp: nil)
        Sentry.metrics_aggregator&.add(:s, key, value, unit: unit, tags: tags, timestamp: timestamp)
      end

      def gauge(key, value, unit: 'none', tags: {}, timestamp: nil)
        Sentry.metrics_aggregator&.add(:g, key, value, unit: unit, tags: tags, timestamp: timestamp)
      end
    end
  end
end
