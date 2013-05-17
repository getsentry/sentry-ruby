module Raven

  class RateLimiter

    # Raven's configuration instance
    attr_accessor :configuration

    # A hash of the current counts for each time period
    attr_accessor :rate_counts

    # A record of when each rate limit was last reset
    attr_accessor :rates_reset_timestamps

    def initialize(configuration)
      @configuration = configuration
      @rate_counts = {}
      @rates_reset_timestamps = {}
    end

    # Returns true if any of the defined rate limits have been exceed
    def limited?
      reset_expired
      rate_counts.each_pair do |period,limit|
        return true if limit > configuration.rate_limits[period]
      end
      return false
    end

    # Increments all rate counts by one
    def increment
      configuration.rate_limits.keys.each do |period|
        rate_counts[period] ||= 0
        rate_counts[period] += 1
      end
    end

    private

    # Resets any rate counts that have expired to 0
    def reset_expired
      configuration.rate_limits.keys.each do |period|
        last_reset = (rates_reset_timestamps[period] ||= Time.now)
        if Time.now - last_reset > period
          rate_counts[period] = 0
          rates_reset_timestamps[period] = Time.now
        end
      end
    end

  end

end
