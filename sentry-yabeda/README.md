<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br>
</p>

# sentry-yabeda, the Yabeda integration for Sentry's Ruby client

---

[![Gem Version](https://img.shields.io/gem/v/sentry-yabeda.svg)](https://rubygems.org/gems/sentry-yabeda)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_yabeda_test.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-yabeda.svg)](https://rubygems.org/gems/sentry-yabeda/)


[Documentation](https://docs.sentry.io/platforms/ruby/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-yabeda"
```

Then initialize Sentry with metrics enabled:

```ruby
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.enable_metrics = true
end
```

That's it! All Yabeda metrics will automatically flow to Sentry.

## How it works

Counters, histograms, summaries, and directly-set gauges all forward to Sentry inline when your app calls them. Yabeda summaries map to Sentry distributions, as Sentry has no summary type.

Collector blocks (`Yabeda.configure { collect { ... } }`) are Yabeda's pull hook — in Prometheus they're triggered by a scrape request. Since Sentry is push-based, `sentry-yabeda` runs a background thread that calls `Yabeda.collect!` every 15 seconds. Metrics populated this way (typically gauges for GC stats, thread counts, etc.) won't carry trace context.
