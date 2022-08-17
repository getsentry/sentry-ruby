# frozen_string_literal: true

require 'cgi'

module Sentry
  class Baggage
    SENTRY_PREFIX = 'sentry-'.freeze
    SENTRY_PREFIX_REGEX = /^sentry-/.freeze

    # DynamicSamplingContext
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

    def initialize(sentry_items, third_party_items: '', mutable: true)
      @sentry_items = sentry_items
      @third_party_items = third_party_items
      @mutable = mutable
    end

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

    def freeze!
      @mutable = false
    end

    def dynamic_sampling_context
      @sentry_items.slice(*DSC_KEYS)
    end

    def serialize(include_third_party: false)
      items = @sentry_items.map { |k, v| "#{SENTRY_PREFIX}#{CGI.escape(k)}=#{CGI.escape(v)}" }
      items << @third_party_items if include_third_party
      items.join(',')
    end
  end
end
