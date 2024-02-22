# frozen_string_literal: true

module Sentry
  # @api private
  class Envelope
    class Item
      STACKTRACE_FRAME_LIMIT_ON_OVERSIZED_PAYLOAD = 500
      MAX_SERIALIZED_PAYLOAD_SIZE = 1024 * 1000

      attr_accessor :headers, :payload, :is_json

      def initialize(headers, payload, is_json: true)
        @headers = headers
        @payload = payload
        @is_json = is_json
      end

      def type
        @headers[:type] || 'event'
      end

      def to_s
        [JSON.generate(@headers), @is_json ? JSON.generate(@payload) : @payload].join("\n")
      end

      def serialize
        result = to_s

        if result.bytesize > MAX_SERIALIZED_PAYLOAD_SIZE
          remove_breadcrumbs!
          result = to_s
        end

        if result.bytesize > MAX_SERIALIZED_PAYLOAD_SIZE
          reduce_stacktrace!
          result = to_s
        end

        [result, result.bytesize > MAX_SERIALIZED_PAYLOAD_SIZE]
      end

      def size_breakdown
        payload.map do |key, value|
          "#{key}: #{JSON.generate(value).bytesize}"
        end.join(", ")
      end

      private

      def remove_breadcrumbs!
        if payload.key?(:breadcrumbs)
          payload.delete(:breadcrumbs)
        elsif payload.key?("breadcrumbs")
          payload.delete("breadcrumbs")
        end
      end

      def reduce_stacktrace!
        if exceptions = payload.dig(:exception, :values) || payload.dig("exception", "values")
          exceptions.each do |exception|
            # in most cases there is only one exception (2 or 3 when have multiple causes), so we won't loop through this double condition much
            traces = exception.dig(:stacktrace, :frames) || exception.dig("stacktrace", "frames")

            if traces && traces.size > STACKTRACE_FRAME_LIMIT_ON_OVERSIZED_PAYLOAD
              size_on_both_ends = STACKTRACE_FRAME_LIMIT_ON_OVERSIZED_PAYLOAD / 2
              traces.replace(
                traces[0..(size_on_both_ends - 1)] + traces[-size_on_both_ends..-1],
              )
            end
          end
        end
      end
    end

    attr_accessor :headers, :items

    def initialize(headers = {})
      @headers = headers
      @items = []
    end

    def add_item(headers, payload, is_json: true)
      @items << Item.new(headers, payload, is_json: is_json)
    end

    def item_types
      @items.map(&:type)
    end

    def event_id
      @headers[:event_id]
    end
  end
end
