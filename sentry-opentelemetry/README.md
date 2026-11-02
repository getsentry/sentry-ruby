<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <picture>
      <source srcset="https://sentry-brand.storage.googleapis.com/sentry-logo-white.png" media="(prefers-color-scheme: dark)" />
      <source srcset="https://sentry-brand.storage.googleapis.com/sentry-wordmark-dark-280x84.png" media="(prefers-color-scheme: light), (prefers-color-scheme: no-preference)" />
      <img src="https://sentry-brand.storage.googleapis.com/sentry-wordmark-dark-280x84.png" alt="Sentry" width="280">
    </picture>
  </a>
  <br>
</p>

# sentry-opentelemetry, the OpenTelemetry integration for Sentry's Ruby client

---


[![Gem Version](https://img.shields.io/gem/v/sentry-opentelemetry.svg)](https://rubygems.org/gems/sentry-opentelemetry)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-opentelemetry.svg)](https://rubygems.org/gems/sentry-opentelemetry/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-opentelemetry&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-opentelemetry&package-manager=bundler&version-scheme=semver)


[Documentation](https://docs.sentry.io/platforms/ruby/guides/opentelemetry/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-rails"
gem "sentry-opentelemetry"

gem "opentelemetry-sdk"
gem "opentelemetry-instrumentation-all"
```

### Configuration

Initialize Sentry for tracing and set the `instrumenter` to `:otel`.
```ruby
# config/initializers/sentry.rb

Sentry.init do |config|
  config.dsn = "MY_DSN"
  config.traces_sample_rate = 1.0
  config.instrumenter = :otel
end
```

This will disable all Sentry instrumentation and rely on the chosen OpenTelemetry tracers for creating spans.

Next, configure OpenTelemetry as per your needs and hook in the Sentry span processor and propagator.

```ruby
# config/initializers/otel.rb

OpenTelemetry::SDK.configure do |c|
  c.use_all
  c.add_span_processor(Sentry::OpenTelemetry::SpanProcessor.instance)
end

OpenTelemetry.propagation = Sentry::OpenTelemetry::Propagator.new
```

