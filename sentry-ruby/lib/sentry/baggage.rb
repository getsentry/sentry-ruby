# frozen_string_literal: true

require "cgi/escape"

module Sentry
  # A {https://www.w3.org/TR/baggage W3C Baggage Header} implementation.
  class Baggage
    SENTRY_PREFIX = "sentry-"
    SENTRY_PREFIX_REGEX = /^sentry-/
    MAX_MEMBER_COUNT = 64
    MAX_BAGGAGE_BYTES = 8192

    # @return [Hash]
    attr_reader :items

    # @return [Boolean]
    attr_reader :mutable

    def initialize(items, mutable: true)
      @items = items
      @mutable = mutable
    end

    # Creates a Baggage object from an incoming W3C Baggage header string.
    #
    # Sentry items are identified with the 'sentry-' prefix and stored in a hash.
    # The presence of a Sentry item makes the baggage object immutable.
    #
    # @param header [String] The incoming Baggage header string.
    # @return [Baggage]
    def self.from_incoming_header(header)
      items = {}
      mutable = true

      header.split(",").each do |item|
        item = item.strip
        key, val = item.split("=")

        next unless key && val
        next unless key =~ SENTRY_PREFIX_REGEX

        baggage_key = key.split("-")[1]
        next unless baggage_key

        items[CGI.unescape(baggage_key)] = CGI.unescape(val)
        mutable = false
      end

      new(items, mutable: mutable)
    end

    # Make the Baggage immutable.
    # @return [void]
    def freeze!
      @mutable = false
    end

    # A {https://develop.sentry.dev/sdk/performance/dynamic-sampling-context/#envelope-header Dynamic Sampling Context}
    # hash to be used in the trace envelope header.
    # @return [Hash]
    def dynamic_sampling_context
      @items
    end

    # Serialize the Baggage object back to a string.
    # @return [String]
    def serialize
      items = @items.map { |k, v| "#{SENTRY_PREFIX}#{CGI.escape(k)}=#{CGI.escape(v)}" }
      items.join(",")
    end

    # Serialize sentry baggage items combined with third-party items from an existing header,
    # respecting W3C limits (max 64 members, max 8192 bytes).
    # Drops third-party items first when limits are exceeded, then sentry items if still over.
    #
    # @param sentry_items [Hash] Sentry baggage items (without sentry- prefix)
    # @param third_party_header [String, nil] Existing baggage header with third-party items
    # @return [String] Combined baggage header string
    def self.serialize_with_third_party(sentry_items, third_party_header)
      # Serialize sentry items
      sentry_baggage_items = sentry_items.map { |k, v| "#{SENTRY_PREFIX}#{CGI.escape(k)}=#{CGI.escape(v)}" }

      # Parse third-party items
      third_party_items = []
      if third_party_header && !third_party_header.empty?
        third_party_header.split(",").each do |item|
          item = item.strip
          next if item.empty?
          next if item =~ SENTRY_PREFIX_REGEX
          third_party_items << item
        end
      end

      # Combine items: sentry first, then third-party
      all_items = sentry_baggage_items + third_party_items

      # Apply limits
      all_items = apply_limits(all_items)

      all_items.join(",")
    end

    private_class_method def self.apply_limits(items)
      # First, enforce member count limit
      # Since sentry items are always first in the array, take(MAX_MEMBER_COUNT)
      # naturally preserves sentry items and drops third-party items first
      items = items.take(MAX_MEMBER_COUNT) if items.size > MAX_MEMBER_COUNT

      # Then, enforce byte size limit
      # Use greedy approach: add items in order until budget exhausted
      result = []
      current_size = 0

      items.each do |item|
        item_size = item.bytesize + (result.empty? ? 0 : 1) # +1 for comma separator
        next if current_size + item_size > MAX_BAGGAGE_BYTES

        result << item
        current_size += item_size
      end

      result
    end
  end
end
