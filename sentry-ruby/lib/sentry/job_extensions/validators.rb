# frozen_string_literal: true

require "sentry/integrable"

module Sentry
  module JobExtensions
    class Validators
      MALFORMED = Object.new.freeze

      EVENT_DATA_KEYS = %i[contexts tags extra].freeze
      SCOPE_DATA_KEYS = (EVENT_DATA_KEYS + %i[user]).freeze

      MESSAGING_DATA_VALIDATORS = {
        system: ->(value) { value.is_a?(String) },
        message_id: ->(value) { value.is_a?(String) },
        destination: ->(value) { value.is_a?(String) },
        receive_latency: ->(value) { value.is_a?(Numeric) }
      }.freeze

      def initialize(event_keys: EVENT_DATA_KEYS, scope_keys: SCOPE_DATA_KEYS, messaging_fields: MESSAGING_DATA_VALIDATORS)
        @event_keys = event_keys.equal?(EVENT_DATA_KEYS) ? event_keys : event_keys.dup.freeze
        @scope_keys = scope_keys.equal?(SCOPE_DATA_KEYS) ? scope_keys : scope_keys.dup.freeze
        @messaging_fields = messaging_fields.equal?(MESSAGING_DATA_VALIDATORS) ? messaging_fields : messaging_fields.dup.freeze
      end

      def known_entries(result, keys)
        result.select { |key, _value| keys.include?(key) }
      end

      def scope_data(result, **)
        normalize_event_data(result, @scope_keys)
      end

      def event_data(result, **)
        normalize_event_data(result, @event_keys)
      end

      def payload(result, payload:, **)
        result.is_a?(payload.class) ? result : MALFORMED
      end

      def normalize_event_data(result, keys)
        return MALFORMED unless result.is_a?(Hash)

        data = known_entries(result, keys)
        return MALFORMED unless data.values.all? { |value| value.is_a?(Hash) }
        return MALFORMED unless data.fetch(:contexts, {}).values.all? { |context| context.is_a?(Hash) }

        data
      end

      def retry_info(result, **)
        return if result.nil?
        return MALFORMED unless result.is_a?(Hash)

        count = result[:count]
        will_retry = result[:will_retry]
        return MALFORMED unless count.is_a?(Integer) && count >= 0 && [true, false].include?(will_retry)

        { count: count, will_retry: will_retry }
      end

      def trace_headers(result, **)
        return if result.nil?
        return MALFORMED unless result.is_a?(Hash) && result.all? { |key, value| key.is_a?(String) && value.is_a?(String) }

        result
      end

      def messaging_data(result, **)
        return MALFORMED unless result.is_a?(Hash)

        data = known_entries(result, @messaging_fields.keys)
        return MALFORMED unless data.all? { |key, value| @messaging_fields.fetch(key).call(value) }

        data
      end

      def label(result, **)
        return if result.nil?
        return MALFORMED unless result.is_a?(String) && !result.empty?

        result
      end

      def decision(result, **)
        return result if result.nil? || result == true || result == false

        MALFORMED
      end

      def integration(result, **)
        return if result.nil?
        return MALFORMED unless result.is_a?(Integrable)

        result
      end
    end
  end
end
