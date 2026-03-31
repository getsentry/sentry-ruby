# sentry-yabeda

A [Yabeda](https://github.com/yabeda-rb/yabeda) adapter that forwards Ruby application metrics to [Sentry](https://sentry.io).

## Installation

Add this line to your application's Gemfile:

```ruby
gem "sentry-yabeda"
```

## Usage

Require `sentry-yabeda` in your application. If you're using Bundler (most cases), simply adding it to your Gemfile is enough.

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.enable_metrics = true
end

# config/initializers/yabeda.rb (or wherever Yabeda is configured)
require "sentry-yabeda"
```

That's it! All Yabeda metrics will automatically flow to Sentry.

### Periodic Gauge Collection

Many Yabeda plugins (puma, gc, gvl\_metrics) measure process-level state using **gauge metrics** with `collect` blocks. These blocks are designed for Prometheus's pull model. A scrape request triggers `Yabeda.collect!`, which reads the current state and sets gauge values.

In a push-based system like Sentry, there's no scrape request. `sentry-yabeda` solves this with a built-in **periodic collector** that calls `Yabeda.collect!` on a background thread:

```ruby
require "sentry-yabeda"

# Start the collector (default: every 15 seconds)
Sentry::Yabeda.start_collector!

# Or with a custom interval
Sentry::Yabeda.start_collector!(interval: 30)

# Stop the collector
Sentry::Yabeda.stop_collector!
```

Without starting the collector, only **event-driven metrics** (counters incremented on each request, histograms measured per-operation) will flow to Sentry. Gauges that depend on periodic collection (e.g. GC stats, GVL contention, and Puma thread pool utilization) require the collector.

** How it works **

Every 15s (or set interval)
1. Collector calls Yabeda.collect!
2. Plugin collect blocks fire (read GC.stat, fetch Puma /stats, etc.)
3. gauge.set(value) calls flow through the adapter
4. Sentry.metrics.gauge(name, value, attributes: tags)
5. Sentry buffers and sends in the next envelope flush

### Metric Type Mapping

| Yabeda Type | Sentry Type |
|-------------|-------------|
| Counter | `Sentry.metrics.count` |
| Gauge | `Sentry.metrics.gauge` |
| Histogram | `Sentry.metrics.distribution` |
| Summary | `Sentry.metrics.distribution` |

### Tags

Yabeda tags are passed directly as Sentry metric attributes, enabling filtering and grouping in the Sentry UI.

### Metric Naming

Metrics are named using the pattern `{group}.{name}` (e.g., `rails.request_duration`). Metrics without a group use just the name.

### Trace Integration

Since Sentry metrics carry trace context automatically, metrics emitted via the adapter are connected to active traces when `sentry-rails` or other Sentry integrations are active. This enables pivoting from metric spikes to relevant traces in the Sentry UI.
