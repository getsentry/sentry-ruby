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
