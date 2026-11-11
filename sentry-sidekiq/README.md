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

By default, `ActiveJob::QueueAdapters::SidekiqAdapter` is listed in `config.rails.skippable_job_adapters`, so ActiveJob jobs running on Sidekiq are reported by `sentry-sidekiq`. Rails apps can opt in to the `sentry-rails` ActiveJob integration instead by removing the adapter from that list:

```ruby
Sentry.init do |config|
  config.rails.skippable_job_adapters.delete("ActiveJob::QueueAdapters::SidekiqAdapter")
end
```

Once opted in, `sentry-rails` reports those jobs under Sidekiq's transaction names and span origin, and `sentry-sidekiq` only reports errors raised before an ActiveJob job starts, such as a job class that can no longer be loaded. Sidekiq's own retry count is not recorded for those jobs, and `config.sidekiq.report_after_job_retries`, `config.sidekiq.report_only_dead_jobs` and the `attempt_threshold` job option only apply to the errors `sentry-sidekiq` reports. Plain Sidekiq jobs are not affected.
