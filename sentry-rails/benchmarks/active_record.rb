#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require "sentry-ruby"
require 'optparse'

require_relative "application"

# Parse command line options
options = { seed: false }
OptionParser.new do |opts|
  opts.banner = "Usage: ruby active_record.rb [options]"

  opts.on("-s", "--seed", "Seed the database before benchmarking") do
    options[:seed] = true
  end

  opts.on("-p", "--posts COUNT", Integer, "Number of posts to generate (default: 100)") do |count|
    ENV['POST_COUNT'] = count.to_s
  end

  opts.on("-c", "--comments COUNT", Integer, "Number of comments to generate (default: 500)") do |count|
    ENV['COMMENT_COUNT'] = count.to_s
  end
end.parse!

app = create_app

if options[:seed]
  puts "Seeding the database..."
  seeds_path = File.join(__dir__, "..", "spec", "dummy", "test_rails_app", "db", "seeds.rb")
  unless File.exist?(seeds_path)
    puts "Error: Could not find seeds.rb at #{seeds_path}"
    exit 1
  end
  load seeds_path
end

puts "\nRunning benchmark..."
Benchmark.ips do |x|
  x.report("master") { app.get("/posts") }
  x.report("branch") { app.get("/posts") }

  x.compare!
end
