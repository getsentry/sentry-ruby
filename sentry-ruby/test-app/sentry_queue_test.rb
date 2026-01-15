#!/usr/bin/env ruby
# frozen_string_literal: true

# Sentry Queue Time Test Generator
#
# USAGE:
#   export SENTRY_DSN='https://your-key@o123.ingest.us.sentry.io/456'
#   export SENTRY_SKIP_SSL_VERIFY=true  # if you get SSL errors
#   ruby sentry_queue_test.rb [duration_minutes] [requests_per_minute] [pattern]
#
# EXAMPLES:
#   ruby sentry_queue_test.rb                    # 5 min, realistic pattern
#   ruby sentry_queue_test.rb 10 30 spike        # 10 min, spike pattern
#   ruby sentry_queue_test.rb 5 20 steady        # 5 min, steady pattern
#
# PATTERNS:
#   realistic   - Business hours pattern (peak 9am-5pm)
#   spike       - Sudden traffic spikes
#   degradation - Gradual performance decline
#   recovery    - System recovering after incident
#   steady      - Consistent baseline
#   wave        - Smooth sine wave

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'rack'
  gem 'sentry-ruby', path: File.expand_path('../../sentry-ruby', __dir__)
end

require 'rack'
require 'sentry-ruby'

# Configuration
DURATION_MINUTES = (ARGV[0] || 5).to_i
REQUESTS_PER_MINUTE = (ARGV[1] || 20).to_i
PATTERN = (ARGV[2] || 'realistic').downcase

# Transaction sequences - realistic API patterns
TRANSACTION_SEQUENCES = {
  user_journey: [
    { path: '/api/products', weight: 0.4 },
    { path: '/api/products/:id', weight: 0.25 },
    { path: '/api/cart', weight: 0.2 },
    { path: '/api/orders', weight: 0.1 },
    { path: '/api/payment', weight: 0.05 }
  ],

  admin: [
    { path: '/api/admin/auth', weight: 0.1 },
    { path: '/api/admin/dashboard', weight: 0.3 },
    { path: '/api/admin/users', weight: 0.25 },
    { path: '/api/admin/reports', weight: 0.2 },
    { path: '/api/admin/analytics', weight: 0.15 }
  ],

  background: [
    { path: '/api/webhooks/stripe', weight: 0.3 },
    { path: '/api/jobs/email', weight: 0.25 },
    { path: '/api/jobs/export', weight: 0.2 },
    { path: '/api/jobs/cleanup', weight: 0.15 },
    { path: '/api/cron/daily', weight: 0.1 }
  ]
}

# Queue time patterns
PATTERNS = {
  'realistic' => lambda do |progress|
    hour_of_day = (progress * 24) % 24
    if hour_of_day >= 9 && hour_of_day <= 17
      base = 40 + (Math.sin((hour_of_day - 9) / 8.0 * Math::PI) * 30)
    else
      base = 10 + rand * 10
    end
    base + (rand * 20 - 10)
  end,

  'spike' => lambda do |progress|
    spike_phase = (progress * 5) % 1
    spike_phase < 0.15 ? 150 + rand * 100 : 15 + rand * 20
  end,

  'degradation' => lambda do |progress|
    base = progress * 200
    base + (rand * 50 - 25)
  end,

  'recovery' => lambda do |progress|
    base = (1 - progress) * 200 + 10
    base + (rand * 30 - 15)
  end,

  'steady' => lambda do |progress|
    30 + rand * 20
  end,

  'wave' => lambda do |progress|
    Math.sin(progress * Math::PI * 2) * 50 + 60 + (rand * 20 - 10)
  end
}

unless PATTERNS.key?(PATTERN)
  puts "\nError: Unknown pattern '#{PATTERN}'"
  puts "\nAvailable patterns: #{PATTERNS.keys.join(', ')}"
  exit 1
end

# Sentry setup
unless ENV['SENTRY_DSN']
  puts "\nError: SENTRY_DSN environment variable not set"
  puts "\nSet it with:"
  puts "  export SENTRY_DSN='https://your-key@o123.ingest.us.sentry.io/456'"
  exit 1
end

skip_ssl = ENV['SENTRY_SKIP_SSL_VERIFY'] == 'true'

Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.traces_sample_rate = 1.0
  config.capture_queue_time = true
  config.transport.ssl_verification = !skip_ssl
end

# App setup
app = lambda { |env| [200, { 'Content-Type' => 'text/plain' }, ['OK']] }
middleware = Sentry::Rack::CaptureExceptions.new(app)

# Helper functions
def weighted_random_endpoint(sequences)
  all_endpoints = sequences.flat_map { |_name, endpoints| endpoints }
  total_weight = all_endpoints.sum { |ep| ep[:weight] }
  random = rand * total_weight

  cumulative = 0
  all_endpoints.each do |endpoint|
    cumulative += endpoint[:weight]
    return endpoint[:path] if random <= cumulative
  end

  all_endpoints.last[:path]
end

def progress_bar(current, total, width = 40)
  percent = (current / total.to_f * 100).round(1)
  filled = (current / total.to_f * width).round
  bar = "█" * filled + "░" * (width - filled)
  "[#{bar}] #{percent}%"
end

def format_time(seconds)
  seconds < 60 ? "#{seconds.round}s" : "#{(seconds / 60).round(1)}min"
end

# Main execution
puts "\nSentry Queue Time Test"
puts "=" * 70
puts "Pattern: #{PATTERN}"
puts "Duration: #{DURATION_MINUTES} minutes"
puts "Frequency: #{REQUESTS_PER_MINUTE} req/min"
puts "Total: #{DURATION_MINUTES * REQUESTS_PER_MINUTE} requests"
puts "\nStarting in 2 seconds... (Ctrl+C to cancel)"
sleep 2

interval_seconds = 60.0 / REQUESTS_PER_MINUTE
start_time = Time.now
end_time = start_time + (DURATION_MINUTES * 60)
request_num = 0

puts "\nGenerating transactions... (Ctrl+C to stop)\n"

begin
  while Time.now < end_time
    request_num += 1
    elapsed_seconds = Time.now - start_time
    elapsed_minutes = elapsed_seconds / 60.0
    progress = elapsed_minutes / DURATION_MINUTES.to_f

    # Generate queue time
    queue_time_ms = PATTERNS[PATTERN].call(progress)
    queue_time_ms = [[queue_time_ms, 1].max, 1000].min

    # Select endpoint
    endpoint = weighted_random_endpoint(TRANSACTION_SEQUENCES)

    # Create request
    request_start_time = Time.now.to_f - (queue_time_ms / 1000.0)

    env = Rack::MockRequest.env_for(endpoint)
    env['HTTP_X_REQUEST_START'] = "t=#{request_start_time}"
    env['REQUEST_METHOD'] = ['GET', 'POST', 'PUT', 'DELETE'].sample

    # Add Puma wait occasionally
    if rand < 0.15
      puma_wait = (rand * 40).round
      env['puma.request_body_wait'] = puma_wait
      actual_queue = [queue_time_ms - puma_wait, 0].max
    else
      actual_queue = queue_time_ms
    end

    # Send transaction
    middleware.call(env)

    # Progress display
    total_requests = DURATION_MINUTES * REQUESTS_PER_MINUTE
    remaining_seconds = end_time - Time.now

    print "\r#{progress_bar(request_num, total_requests)} "
    print "#{request_num}/#{total_requests} | "
    print "Queue: #{actual_queue.round(1)}ms | "
    print "Remaining: #{format_time(remaining_seconds)}   "
    $stdout.flush

    sleep interval_seconds
  end

  print "\r" + " " * 100 + "\r"

rescue Interrupt
  print "\r" + " " * 100 + "\r"
  puts "\nStopped by user"
end

# Summary
duration = ((Time.now - start_time) / 60.0).round(2)

puts "\n" + "=" * 70
puts "Complete"
puts "=" * 70
puts "\nDuration: #{duration} minutes"
puts "Requests: #{request_num}"
puts "Pattern: #{PATTERN}"
