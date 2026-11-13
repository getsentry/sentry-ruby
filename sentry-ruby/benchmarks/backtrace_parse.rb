# frozen_string_literal: true

# Allocations and throughput for capturing the same exception repeatedly with a
# Rails-sized (120 frame) backtrace. Run it on two checkouts to compare them:
#
#   bundle exec ruby benchmarks/backtrace_parse.rb

require "benchmark/ips"
require "memory_profiler"
require "sentry-ruby"

class NullTransport < Sentry::Transport
  def send_data(*); end
end

Sentry.init do |config|
  config.sdk_logger = ::Logger.new(nil)
  config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
  config.transport.transport_class = NullTransport
  config.background_worker_threads = 0
end

GEM_FRAMES = [
  ["actionpack-8.0.2/lib/action_controller/metal/basic_implicit_render.rb", 8, "send_action"],
  ["actionpack-8.0.2/lib/abstract_controller/base.rb", 226, "process_action"],
  ["actionpack-8.0.2/lib/action_controller/metal/rendering.rb", 193, "process_action"],
  ["actionpack-8.0.2/lib/abstract_controller/callbacks.rb", 261, "block in process_action"],
  ["activesupport-8.0.2/lib/active_support/callbacks.rb", 120, "block in run_callbacks"],
  ["actiontext-8.0.2/lib/action_text/rendering.rb", 25, "with_renderer"],
  ["activesupport-8.0.2/lib/active_support/callbacks.rb", 129, "run_callbacks"],
  ["actionpack-8.0.2/lib/action_dispatch/journey/router.rb", 53, "block in serve"],
  ["rack-3.1.12/lib/rack/etag.rb", 29, "call"],
  ["rack-3.1.12/lib/rack/conditional_get.rb", 31, "call"],
  ["railties-8.0.2/lib/rails/rack/logger.rb", 41, "call_app"],
  ["puma-6.6.0/lib/puma/request.rb", 99, "block in handle_request"],
  ["puma-6.6.0/lib/puma/thread_pool.rb", 173, "block in spawn_thread"]
].freeze

# Every 6th frame is app code, the rest are gems.
BACKTRACE = Array.new(120) do |i|
  if i % 6 == 0
    "/app/app/models/order_#{i}.rb:#{10 + i}:in `compute_#{i}'"
  else
    path, line, meth = GEM_FRAMES[i % GEM_FRAMES.size]
    "/usr/local/bundle/gems/#{path}:#{line + i}:in `#{meth}'"
  end
end.freeze

def build_exception
  e = RuntimeError.new("boom")
  e.set_backtrace(BACKTRACE.map(&:dup)) # fresh strings, like a real raise
  e
end

in_app_pattern = Regexp.new("^(/app/)?#{Sentry::Configuration::APP_DIRS_PATTERN}")

# Warm every cache (parse cache, filename cache, line cache).
5.times { Sentry.capture_exception(build_exception) }

ITER = 100
backtraces = Array.new(ITER) { BACKTRACE.map(&:dup) }
parse_report = MemoryProfiler.report do
  backtraces.each { |bt| Sentry::Backtrace.parse(bt, nil, nil, in_app_pattern: in_app_pattern) }
end

exceptions = Array.new(ITER) { build_exception }
capture_report = MemoryProfiler.report do
  exceptions.each { |e| Sentry.capture_exception(e) }
end

puts "ruby #{RUBY_VERSION}, #{BACKTRACE.size}-frame backtrace, #{ITER} iterations"
puts format("Backtrace.parse:   %6d objects / %8d bytes per call",
            parse_report.total_allocated / ITER, parse_report.total_allocated_memsize / ITER)
puts format("capture_exception: %6d objects / %8d bytes per call",
            capture_report.total_allocated / ITER, capture_report.total_allocated_memsize / ITER)

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)
  x.report("Backtrace.parse") { Sentry::Backtrace.parse(BACKTRACE, nil, nil, in_app_pattern: in_app_pattern) }
  x.report("capture_exception") { Sentry.capture_exception(build_exception) }
end
