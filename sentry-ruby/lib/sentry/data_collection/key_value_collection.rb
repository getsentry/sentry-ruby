# frozen_string_literal: true

module Sentry
  class DataCollection
    # Configuration for key-value data collection.
    class KeyValueCollection
      FILTERED_VALUE = "[Filtered]"

      # Keys from this list are ALWAYS filtered, regardless of :mode
      # TODO-neel-data cookies have separate list, see JS
      SENSITIVE_DENY_LIST = %w[
        auth
        token
        secret
        session
        password
        passwd
        pwd
        key
        jwt
        bearer
        sso
        saml
        csrf
        xsrf
        credentials
        sid
        identity
        cookie
        set-cookie
      ].freeze

      # `mode` controls whether values are collected:
      # - `:off` disables collection.
      # - `:deny_list` collects values except those matching `terms`.
      # - `:allow_list` collects only values matching `terms`.
      # @return [:off, :deny_list, :allow_list]
      attr_accessor :mode

      # `terms` contains the keys or patterns used by the selected mode.
      # @return [Array<String>, nil]
      attr_reader :terms

      def initialize(mode:, terms:)
        @mode = mode
        self.terms = terms
      end

      def terms=(terms)
        @terms = terms&.map { |term| term.to_s.downcase }&.reject { |term| term.strip.empty? }
      end

      # Applies this collection configuration without changing the input hash.
      # Keys are retained whenever the category is collected; values that are not
      # safe to send are replaced with FILTERED_VALUE.
      #
      # @param values [Hash] key-value data to filter
      # @return [Hash] a new filtered hash, or an empty hash when collection is off
      def filter(values)
        return {} if mode == :off

        values.each_with_object({}) do |(key, value), filtered|
          filtered[key] = safe_value?(key) ? value : FILTERED_VALUE
        end
      end

      private

      def safe_value?(key)
        key_downcase = key.to_s.downcase
        return false if sensitive?(key_downcase)

        case mode
        when :deny_list
          !matches_any_term?(key_downcase)
        when :allow_list
          matches_any_term?(key_downcase)
        else
          false
        end
      end

      def sensitive?(key)
        SENSITIVE_DENY_LIST.any? { |term| key.include?(term) }
      end

      def matches_any_term?(key)
        @terms&.any? { |term| key.include?(term) }
      end
    end
  end
end
