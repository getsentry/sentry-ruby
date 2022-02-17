# frozen_string_literal: true

module Sentry
  # @api private
  class Envelope
    class Item
      attr_reader :headers, :payload

      def initialize(headers, payload)
        @headers = headers
        @payload = payload
      end

      def type
        @headers[:type] || @headers['type'] || 'event'
      end

      def to_s
        <<~ITEM
          #{JSON.generate(@headers)}
          #{JSON.generate(@payload)}
        ITEM
      end
    end

    attr_reader :headers, :items

    def initialize(headers = {})
      @headers = headers
      @items = []
    end

    def add_item(headers, payload)
      @items << Item.new(headers, payload)
    end

    def to_s
      [JSON.generate(@headers), *@items.map(&:to_s)].join("\n")
    end
  end
end
