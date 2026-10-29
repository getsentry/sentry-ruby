# frozen_string_literal: true

module Sentry
  module JobExtensions
    # @api private
    class Instrumentation
      MESSAGING_DATA_ATTRIBUTES = {
        system: Span::DataConventions::MESSAGING_SYSTEM,
        message_id: Span::DataConventions::MESSAGING_MESSAGE_ID,
        destination: Span::DataConventions::MESSAGING_DESTINATION_NAME,
        receive_latency: Span::DataConventions::MESSAGING_MESSAGE_RECEIVE_LATENCY
      }.freeze

      attr_reader :registry

      def initialize(registry: Sentry.job_extensions)
        @registry = registry
      end

      private

      def set_messaging_data(span, data)
        data.each do |key, value|
          span.set_data(MESSAGING_DATA_ATTRIBUTES.fetch(key), value)
        end
      end

      def set_retry_count(span, extension, job, default: nil)
        info = registry.call(extension, :retry_info, job: job)
        count = info ? info[:count] : default
        span.set_data(Span::DataConventions::MESSAGING_MESSAGE_RETRY_COUNT, count) if count
      end

      def resolve(value)
        value.respond_to?(:call) ? value.call : value
      end
    end
  end
end
