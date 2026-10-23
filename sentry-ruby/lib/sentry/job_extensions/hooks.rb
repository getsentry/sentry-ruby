# frozen_string_literal: true

require "sentry/integrable"

module Sentry
  module JobExtensions
    # @!visibility private
    class Hooks
      MALFORMED = Validators::MALFORMED

      class Contract
        def initialize(validator, fallback:)
          @validator = validator
          @fallback = fallback
          freeze
        end

        def fallback_result(arguments)
          @fallback.call(**arguments)
        end

        def normalize(validators, result, arguments)
          validators.public_send(@validator, result, **arguments)
        end
      end

      EMPTY_HASH = ->(**) { {} }.freeze
      NO_OVERRIDE = ->(**) { nil }.freeze
      ORIGINAL_PAYLOAD = ->(payload:, **) { payload }.freeze

      CONTRACTS = {
        scope_data: Contract.new(:scope_data, fallback: EMPTY_HASH),
        error_data: Contract.new(:event_data, fallback: EMPTY_HASH),
        messaging_data: Contract.new(:messaging_data, fallback: EMPTY_HASH),
        retry_info: Contract.new(:retry_info, fallback: NO_OVERRIDE),
        inject_trace_headers: Contract.new(:payload, fallback: ORIGINAL_PAYLOAD),
        extract_trace_headers: Contract.new(:trace_headers, fallback: NO_OVERRIDE),
        integration: Contract.new(:integration, fallback: NO_OVERRIDE),
        producer: Contract.new(:producer, fallback: NO_OVERRIDE),
        publish_messaging_data: Contract.new(:messaging_data, fallback: EMPTY_HASH)
      }.merge(
        %i[report_exception? report_retried_exception?]
          .to_h { |hook| [hook, Contract.new(:decision, fallback: NO_OVERRIDE)] },
        %i[transaction_name span_origin publish_description]
          .to_h { |hook| [hook, Contract.new(:label, fallback: NO_OVERRIDE)] }
      ).freeze

      def initialize(validators: Validators.new)
        @validators = validators
      end

      def normalize(hook, result, arguments)
        fetch(hook).normalize(@validators, result, arguments)
      end

      def fallback_result(hook, arguments)
        fetch(hook).fallback_result(arguments)
      end

      private

      def fetch(hook)
        CONTRACTS.fetch(hook) do
          raise ArgumentError, "unknown job extension hook #{hook.inspect}, expected one of #{CONTRACTS.keys.inspect}"
        end
      end
    end
  end
end
