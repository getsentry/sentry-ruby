# frozen_string_literal: true

require 'cgi'

module Sentry
  # A {https://www.w3.org/TR/baggage W3C Baggage Header} implementation.
  class Baggage
    SENTRY_PREFIX = 'sentry-'.freeze
    SENTRY_PREFIX_REGEX = /^sentry-/.freeze

    DSC_KEYS = %w(
      trace_id
      public_key
      sample_rate
      release
      environment
      transaction
      user_id
      user_segment
    ).freeze

    # @return [Boolean]
    attr_reader :mutable

    def initialize(sentry_items, third_party_items: '', mutable: true)
      @sentry_items = sentry_items
      @third_party_items = third_party_items
      @mutable = mutable
    end

    # Creates a Baggage object from an incoming W3C Baggage header string.
    #
    # Sentry items are identified with the 'sentry-' prefix and stored in a hash.
    # Third party items are stored verbatim in a separate string.
    # The presence of a Sentry item makes the baggage object immutable.
    #
    # @param header [String] The incoming Baggage header string.
    # @return [Baggage, nil]
    def self.from_incoming_header(header)
      return nil if header.nil? || header.empty?

      sentry_items = {}
      third_party_items = ''
      mutable = true

      header.split(',').map(&:strip).each do |item|
        key, val = item.split('=')
        next unless key && val

        if key =~ SENTRY_PREFIX_REGEX
          baggage_key = CGI.unescape(key.split('-')[1])
          sentry_items[baggage_key] = CGI.unescape(val)
          mutable = false
        else
          delim = third_party_items.empty? ? '' : ','
          third_party_items += (delim + item)
        end
      end

      new(sentry_items, third_party_items: third_party_items, mutable: mutable)
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
      @sentry_items.slice(*DSC_KEYS)
    end

    # Serialize the Baggage object back to a string.
    # @param include_third_party [Boolean]
    # @return [String]
    def serialize(include_third_party: false)
      items = @sentry_items.map { |k, v| "#{SENTRY_PREFIX}#{CGI.escape(k)}=#{CGI.escape(v)}" }
      items << @third_party_items if include_third_party
      items.join(',')
    end
  end
end
