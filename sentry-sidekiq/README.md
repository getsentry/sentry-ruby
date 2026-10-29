<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br>
</p>

# sentry-sidekiq, the Sidekiq integration for Sentry's Ruby client

---


[![Gem Version](https://img.shields.io/gem/v/sentry-sidekiq.svg)](https://rubygems.org/gems/sentry-sidekiq)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-sidekiq.svg)](https://rubygems.org/gems/sentry-sidekiq/)

[Documentation](https://docs.sentry.io/platforms/ruby/guides/sidekiq/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-sidekiq"
```

Then you're all set! `sentry-sidekiq` will automatically insert a custom middleware and error handler to capture exceptions from your workers!

### ActiveJob on Sidekiq

By default, `config.sidekiq.active_job_integration = :sidekiq` keeps ActiveJob jobs running on Sidekiq reported by `sentry-sidekiq`, exactly as before. Rails apps can opt in to the `sentry-rails` ActiveJob integration instead:

```ruby
Sentry.init do |config|
  config.sidekiq.active_job_integration = :rails
end
```

Once opted in, `sentry-rails` reports those jobs and `sentry-sidekiq` enriches them with Sidekiq data. If `ActiveJob::QueueAdapters::SidekiqAdapter` is listed in `config.rails.skippable_job_adapters`, `sentry-sidekiq` keeps reporting those jobs itself. Plain Sidekiq jobs are not affected by this setting.

Errors from ActiveJob jobs on Sidekiq that `retry_on` retries are not reported, regardless of `config.rails.active_job_report_on_retry_error`.
