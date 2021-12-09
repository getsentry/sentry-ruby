require 'benchmark/ips'

def raise_n_exceptions(n, with_sleep: false)
  n.times do |i|
    raise "exception: #{i}" rescue nil
  end
  sleep(0.05) if with_sleep
end

def raise_n_exceptions_with_tracepoint(n, with_sleep: false)
  TracePoint.new(:raise) do |tp|
    exception = tp.raised_exception

    next if exception.instance_variable_get(:@sentry_locals)

    locals = tp.binding.local_variables.each_with_object({}) do |local, result|
      result[local] = tp.binding.local_variable_get(local)
    end

    exception.instance_variable_set(:@sentry_locals, locals)
  end.enable do
    raise_n_exceptions(n, with_sleep: with_sleep)
  end
end

# Warming up --------------------------------------
#  raise 50 exceptions     1.919k i/100ms
# raise 50 exceptions with tracepoint
#                        537.000  i/100ms
# Calculating -------------------------------------
#  raise 50 exceptions     18.803k (± 2.1%) i/s -     94.031k
# raise 50 exceptions with tracepoint
#                           5.333k (± 3.8%) i/s -     26.850k

# Comparison:
#  raise 50 exceptions:    18803.0 i/s
# raise 50 exceptions with tracepoint:     5332.8 i/s - 3.53x slower

Benchmark.ips do |x|
  x.report("raise 50 exceptions") { raise_n_exceptions(50) }
  x.report("raise 50 exceptions with tracepoint") { raise_n_exceptions_with_tracepoint(50) }
  x.compare!
end


# Warming up --------------------------------------
# (with 50ms sleep) raise 50 exceptions
#                          1.000  i/100ms
# (with 50ms sleep) raise 50 exceptions with tracepoint
#                          1.000  i/100ms
# Calculating -------------------------------------
# (with 50ms sleep) raise 50 exceptions
#                          19.032  (± 5.3%) i/s -     96.000
# (with 50ms sleep) raise 50 exceptions with tracepoint
#                          18.953  (± 5.3%) i/s -     95.000

# Comparison:
# (with 50ms sleep) raise 50 exceptions:       19.0 i/s
# (with 50ms sleep) raise 50 exceptions with tracepoint:       19.0 i/s - same-ish: difference falls within error

Benchmark.ips do |x|
  x.report("(with 50ms sleep) raise 50 exceptions") { raise_n_exceptions(50, with_sleep: true) }
  x.report("(with 50ms sleep) raise 50 exceptions with tracepoint") { raise_n_exceptions_with_tracepoint(50, with_sleep: true) }
  x.compare!
end
