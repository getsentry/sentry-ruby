#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "active_support/backtrace_cleaner"

# Simulate the current implementation
class CurrentImplementation
  CLEAN_FRAME_CACHE_SIZE = 1000

  def initialize
    @clean_frame_cache = {}
    @clean_frame_cache_mutex = Mutex.new
    @backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.add_silencer { |line| line.include?("sentry-ruby/lib") || line.include?("sentry-rails/lib") }
    end
  end

  def cached_clean_frame(location)
    cache_key = "#{location.absolute_path}:#{location.lineno}"

    # Fast path: check cache without lock
    cached_result = @clean_frame_cache[cache_key]
    return cached_result if cached_result

    # Slow path: compute and cache the result
    frame = @backtrace_cleaner.clean_frame(location)

    # Only cache if we got a result (non-nil)
    if frame
      @clean_frame_cache_mutex.synchronize do
        # Implement simple LRU by removing oldest entry when cache is full
        if @clean_frame_cache.size >= CLEAN_FRAME_CACHE_SIZE
          @clean_frame_cache.shift # Remove oldest entry
        end
        @clean_frame_cache[cache_key] = frame
      end
    end

    frame
  end
end

# No caching - baseline
class NoCache
  def initialize
    @backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.add_silencer { |line| line.include?("sentry-ruby/lib") || line.include?("sentry-rails/lib") }
    end
  end

  def cached_clean_frame(location)
    @backtrace_cleaner.clean_frame(location)
  end
end

# Optimized: Use frozen array keys, no mutex
class OptimizedCache
  CLEAN_FRAME_CACHE_SIZE = 1000

  def initialize
    @clean_frame_cache = {}
    @backtrace_cleaner = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
      cleaner.add_silencer { |line| line.include?("sentry-ruby/lib") || line.include?("sentry-rails/lib") }
    end
  end

  def cached_clean_frame(location)
    # Use frozen array as cache key to avoid string allocation
    cache_key = [location.absolute_path, location.lineno].freeze

    # Check cache (Hash reads are thread-safe in MRI)
    cached_result = @clean_frame_cache[cache_key]
    return cached_result if cached_result

    # Compute result
    frame = @backtrace_cleaner.clean_frame(location)

    # Cache without lock (benign race condition acceptable)
    if frame && @clean_frame_cache.size < CLEAN_FRAME_CACHE_SIZE
      @clean_frame_cache[cache_key] = frame
    end

    frame
  end
end

puts "Ruby version: #{RUBY_VERSION}"
puts

# Simulate realistic query patterns
def simulate_queries(impl, pattern:)
  case pattern
  when :same_location
    # Same query from same location (100% cache hit rate)
    location = caller_locations(0, 1).first
    100.times { impl.cached_clean_frame(location) }
  when :different_locations
    # Different queries from different locations (0% cache hit rate)
    100.times { impl.cached_clean_frame(caller_locations(0, 1).first) }
  when :realistic
    # Mix: 80% from same 5 locations, 20% from unique locations
    common_locations = 5.times.map { caller_locations(0, 1).first }
    100.times do |i|
      if i % 5 == 0
        impl.cached_clean_frame(caller_locations(0, 1).first) # unique
      else
        impl.cached_clean_frame(common_locations.sample) # common
      end
    end
  end
end

puts "=" * 80
puts "Scenario 1: Same location (100% cache hit - best case for caching)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("no cache") do
    simulate_queries(NoCache.new, pattern: :same_location)
  end

  x.report("current (mutex)") do
    simulate_queries(CurrentImplementation.new, pattern: :same_location)
  end

  x.report("optimized (no mutex)") do
    simulate_queries(OptimizedCache.new, pattern: :same_location)
  end

  x.compare!
end

puts
puts "=" * 80
puts "Scenario 2: Different locations (0% cache hit - worst case for caching)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("no cache") do
    simulate_queries(NoCache.new, pattern: :different_locations)
  end

  x.report("current (mutex)") do
    simulate_queries(CurrentImplementation.new, pattern: :different_locations)
  end

  x.report("optimized (no mutex)") do
    simulate_queries(OptimizedCache.new, pattern: :different_locations)
  end

  x.compare!
end

puts
puts "=" * 80
puts "Scenario 3: Realistic mix (80% common, 20% unique)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("no cache") do
    simulate_queries(NoCache.new, pattern: :realistic)
  end

  x.report("current (mutex)") do
    simulate_queries(CurrentImplementation.new, pattern: :realistic)
  end

  x.report("optimized (no mutex)") do
    simulate_queries(OptimizedCache.new, pattern: :realistic)
  end

  x.compare!
end
