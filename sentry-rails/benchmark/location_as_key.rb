#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"

puts "Ruby version: #{RUBY_VERSION}"
puts

# Test if Thread::Backtrace::Location objects can be used as hash keys
locations = caller_locations(0, 10)

puts "=" * 80
puts "Testing Thread::Backtrace::Location as hash key"
puts "=" * 80
puts

# Test 1: Can we use location objects as keys?
hash = {}
locations.each_with_index do |loc, i|
  hash[loc] = "value_#{i}"
end

puts "✓ Can use location objects as hash keys"
puts "  Hash size: #{hash.size}"
puts

# Test 2: Are location objects unique per call site?
loc1 = caller_locations(0, 1).first
loc2 = caller_locations(0, 1).first

puts "Location object identity:"
puts "  loc1.object_id: #{loc1.object_id}"
puts "  loc2.object_id: #{loc2.object_id}"
puts "  loc1 == loc2: #{loc1 == loc2}"
puts "  loc1.eql?(loc2): #{loc1.eql?(loc2)}"
puts "  loc1.hash == loc2.hash: #{loc1.hash == loc2.hash}"
puts

# Test 3: Do location objects from the same line have the same hash?
def test_method
  caller_locations(0, 1).first
end

loc_a = test_method
loc_b = test_method

puts "Same method, different calls:"
puts "  loc_a.object_id: #{loc_a.object_id}"
puts "  loc_b.object_id: #{loc_b.object_id}"
puts "  loc_a == loc_b: #{loc_a == loc_b}"
puts "  loc_a.eql?(loc_b): #{loc_a.eql?(loc_b)}"
puts "  loc_a.hash == loc_b.hash: #{loc_a.hash == loc_b.hash}"
puts "  loc_a.absolute_path == loc_b.absolute_path: #{loc_a.absolute_path == loc_b.absolute_path}"
puts "  loc_a.lineno == loc_b.lineno: #{loc_a.lineno == loc_b.lineno}"
puts

# Test 4: Hash lookup behavior
test_hash = {}
test_hash[loc_a] = "first"
test_hash[loc_b] = "second"

puts "Hash lookup with location objects:"
puts "  test_hash.size: #{test_hash.size}"
puts "  test_hash[loc_a]: #{test_hash[loc_a]}"
puts "  test_hash[loc_b]: #{test_hash[loc_b]}"
puts

# Test 5: What about using location as key in Thread.each_caller_location?
puts "Testing with Thread.each_caller_location:"
cache = {}
count = 0
locations_seen = []

Thread.each_caller_location do |location|
  count += 1
  locations_seen << location
  if cache[location]
    puts "  ✓ Found cached location at iteration #{count}"
  else
    cache[location] = true
  end
  break if count >= 10
end

puts "  Total iterations: #{count}"
puts "  Cache size: #{cache.size}"
puts "  All locations unique? #{locations_seen.size == locations_seen.uniq.size}"
puts

# Test 5b: Call the same code path twice
def recursive_test(depth, cache)
  return if depth == 0
  Thread.each_caller_location do |location|
    if cache[location]
      return :cache_hit
    else
      cache[location] = true
    end
  end
  recursive_test(depth - 1, cache)
end

puts "Testing cache across multiple calls to same code:"
shared_cache = {}
result1 = recursive_test(2, shared_cache)
result2 = recursive_test(2, shared_cache)
puts "  First call result: #{result1.inspect}"
puts "  Second call result: #{result2.inspect}"
puts "  Cache size: #{shared_cache.size}"
puts

# Test 6: Performance comparison
require "benchmark/ips"

locations_sample = caller_locations(0, 20)

puts "=" * 80
puts "Performance comparison: Different cache key strategies"
puts "=" * 80
puts

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  x.report("location object as key (doesn't work)") do
    cache = {}
    locations_sample.each do |loc|
      cache[loc] ||= "cached"
    end
  end

  x.report("array [path, lineno] (not frozen)") do
    cache = {}
    locations_sample.each do |loc|
      key = [loc.absolute_path, loc.lineno]
      cache[key] ||= "cached"
    end
  end

  x.report("frozen array [path, lineno]") do
    cache = {}
    locations_sample.each do |loc|
      key = [loc.absolute_path, loc.lineno].freeze
      cache[key] ||= "cached"
    end
  end

  x.report("string interpolation") do
    cache = {}
    locations_sample.each do |loc|
      key = "#{loc.absolute_path}:#{loc.lineno}"
      cache[key] ||= "cached"
    end
  end

  x.compare!
end
