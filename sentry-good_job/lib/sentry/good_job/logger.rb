# frozen_string_literal: true

# Centralized logging utility for Sentry Good Job integration
module Sentry
  module GoodJob
    module Logger
      def self.enabled?
        ::Sentry.configuration.good_job.logging_enabled && logger.present?
      end

      def self.logger
        if ::Sentry.configuration.good_job.logger
          ::Sentry.configuration.good_job.logger
        elsif defined?(::Rails) && ::Rails.respond_to?(:logger)
          ::Rails.logger
        else
          nil
        end
      end

      def self.info(message)
        return unless enabled?

        logger.info(message)
      end

      def self.warn(message)
        return unless enabled?

        logger.warn(message)
      end

      def self.error(message)
        return unless enabled?

        logger.error(message)
      end
    end
  end
end
