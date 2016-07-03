require 'benchmark/ips'
require 'raven'
require 'rack/test'
require 'securerandom'

def generate_random_json
  (1..1_000_000).map do |i|
    [SecureRandom.base64, SecureRandom.base64]
  end.to_h.to_json
end

Processor = Raven::Processor::SanitizeData.new(Raven.client)
ExampleData = { :example => generate_random_json }

Benchmark.ips do |x|
  x.config(:time => 60, :warmup => 5)
  x.report("simple") { Processor.process(ExampleData) }
  x.compare!
end
