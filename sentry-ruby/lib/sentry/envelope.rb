# frozen_string_literal: true

module Sentry
  # @api private
  class Envelope
    class Item
      attr_accessor :headers, :payload

      def initialize(headers, payload)
        @headers = headers
        @payload = payload
      end

      def type
        @headers[:type] || 'event'
      end

      def to_s
        <<~ITEM
          #{JSON.generate(@headers)}
          #{JSON.generate(@payload)}
        ITEM
      end
    end

    attr_accessor :headers, :items

    def initialize(headers = {})
      @headers = headers
      @items = []
    end

    def add_item(headers, payload)
      @items << Item.new(headers, payload)
    end

    def item_types
      @items.map(&:type)
    end

    def event_id
      @headers[:event_id]
    end
  end
end
