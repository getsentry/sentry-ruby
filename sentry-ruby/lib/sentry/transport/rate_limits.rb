# frozen_string_literal: true

module Sentry
  class Transport
    # The times until which data categories are rate limited. The +nil+ category holds the
    # limit that applies to all categories.
    #
    # {#update} is the only write operation, and it never moves a deadline earlier, so a
    # shorter rate limit can never replace a longer one, as the
    # {https://develop.sentry.dev/sdk/foundations/transport/rate-limiting/#stage-2-determine-rate-limits
    # rate limiting spec} requires.
    #
    # @api private
    class RateLimits
      def initialize
        @deadlines = {}
      end

      # Extends the rate limit for the category to the deadline, unless it already ends later.
      # @param category [String, nil] the data category, or +nil+ for all categories
      # @param deadline [Time]
      # @return [void]
      def update(category, deadline)
        current = @deadlines[category]
        @deadlines[category] = deadline if current.nil? || deadline > current
        nil
      end

      # @param category [String]
      # @return [Boolean] whether the category, or all categories, are rate limited now
      def limited?(category)
        now = Time.now
        [@deadlines[category], @deadlines[nil]].any? { |deadline| deadline && deadline > now }
      end

      # @return [Boolean] whether any category is rate limited now
      def any_limited?
        now = Time.now
        @deadlines.each_value.any? { |deadline| deadline > now }
      end

      # @return [Hash{String, nil => Time}] a copy of the deadlines; changing it does not change the rate limits
      def to_h
        @deadlines.dup
      end
    end
  end
end
