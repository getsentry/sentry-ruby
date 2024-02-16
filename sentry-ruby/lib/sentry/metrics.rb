# frozen_string_literal: true

require 'sentry/metrics/metric'
require 'sentry/metrics/counter_metric'
require 'sentry/metrics/distribution_metric'
require 'sentry/metrics/gauge_metric'
require 'sentry/metrics/set_metric'

module Sentry
  module Metrics
    class << self
      # TODO-neel-metrics define units, maybe symbols
      def incr(key, value: 1.0, unit: 'none', tags: nil, timestamp: nil)
      end
    end
  end
end
