# frozen_string_literal: true

require "sentry/metric_event"

module Sentry
  module Metrics
    class << self
      # Increments a counter metric
      # @param name [String] the metric name
      # @param value [Numeric] the value to increment by (default: 1)
      # @param attributes [Hash, nil] additional attributes for the metric (optional)
      # @return [void]
      def count(name, value: 1, attributes: nil)
        return unless Sentry.initialized?

        Sentry.get_current_hub.capture_metric(
          name: name,
          type: :counter,
          value: value,
          attributes: attributes
        )
      end

      # Records a gauge metric
      # @param name [String] the metric name
      # @param value [Numeric] the gauge value
      # @param unit [String, nil] the metric unit (optional)
      # @param attributes [Hash, nil] additional attributes for the metric (optional)
      # @return [void]
      def gauge(name, value, unit: nil, attributes: nil)
        return unless Sentry.initialized?

        Sentry.get_current_hub.capture_metric(
          name: name,
          type: :gauge,
          value: value,
          unit: unit,
          attributes: attributes
        )
      end

      # Records a distribution metric
      # @param name [String] the metric name
      # @param value [Numeric] the distribution value
      # @param unit [String, nil] the metric unit (optional)
      # @param attributes [Hash, nil] additional attributes for the metric (optional)
      # @return [void]
      def distribution(name, value, unit: nil, attributes: nil)
        return unless Sentry.initialized?

        Sentry.get_current_hub.capture_metric(
          name: name,
          type: :distribution,
          value: value,
          unit: unit,
          attributes: attributes
        )
      end
    end
  end
end
