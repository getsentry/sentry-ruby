require 'benchmark/ips'
require 'raven'
require 'rack/test'
require 'securerandom'
# YAJL improves Raven's JSON perf by approximately ~20%
# require 'yajl'
# require 'yajl/json_gem'

def generate_random_json
  (1..1_000_000).map do
    [SecureRandom.base64, SecureRandom.base64]
  end.to_h.to_json
end

PROCESSOR = Raven::Processor::SanitizeData.new(Raven.client)
example_data = { :example => generate_random_json }

Benchmark.ips do |x|
  x.config(:time => 60, :warmup => 5)
  x.report("simple") { PROCESSOR.process(example_data) }
  x.compare!
end
