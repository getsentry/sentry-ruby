# frozen_string_literal: true

require "yabeda/base_adapter"

module Sentry
  module Yabeda
    class Adapter < ::Yabeda::BaseAdapter
      # Sentry does not require pre-registration of metrics
      def register_counter!(_metric); end
      def register_gauge!(_metric); end
      def register_histogram!(_metric); end
      def register_summary!(_metric); end

      def perform_counter_increment!(counter, tags, increment)
        return unless enabled?

        Sentry.metrics.count(
          metric_name(counter),
          value: increment,
          attributes: attributes_for(tags)
        )
      end

      def perform_gauge_set!(gauge, tags, value)
        return unless enabled?

        Sentry.metrics.gauge(
          metric_name(gauge),
          value,
          unit: unit_for(gauge),
          attributes: attributes_for(tags)
        )
      end

      def perform_histogram_measure!(histogram, tags, value)
        return unless enabled?

        Sentry.metrics.distribution(
          metric_name(histogram),
          value,
          unit: unit_for(histogram),
          attributes: attributes_for(tags)
        )
      end

      def perform_summary_observe!(summary, tags, value)
        return unless enabled?

        Sentry.metrics.distribution(
          metric_name(summary),
          value,
          unit: unit_for(summary),
          attributes: attributes_for(tags)
        )
      end

      private

      def enabled?
        Sentry.initialized? && Sentry.configuration.enable_metrics
      end

      def attributes_for(tags)
        tags.empty? ? nil : tags
      end

      def metric_name(metric)
        [metric.group, metric.name].compact.join(".")
      end

      # TODO: Normalize Yabeda unit symbols (e.g. :milliseconds) to Sentry's
      # canonical singular strings (e.g. "millisecond") once units are visible
      # in the Sentry product. See https://develop.sentry.dev/sdk/foundations/state-management/scopes/attributes/#units
      def unit_for(metric)
        metric.unit&.to_s
      end
    end
  end
end
