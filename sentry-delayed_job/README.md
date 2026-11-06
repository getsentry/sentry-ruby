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

# sentry-delayed_job, the DelayedJob integration for Sentry's Ruby client

---


[![Gem Version](https://img.shields.io/gem/v/sentry-delayed_job.svg)](https://rubygems.org/gems/sentry-delayed_job)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-delayed_job.svg)](https://rubygems.org/gems/sentry-delayed_job/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-delayed_job&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-delayed_job&package-manager=bundler&version-scheme=semver)


[Documentation](https://docs.sentry.io/platforms/ruby/guides/delayed_job/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-delayed_job"
```

Then you're all set! `sentry-delayed_job` captures exceptions and starts a `queue.delayed_job` transaction for every job your delayed_job workers perform.

## Maintenance Mode

`sentry-delayed_job` is in maintenance mode. The integration for plain delayed_job jobs keeps receiving fixes, but new background job features land in `sentry-rails` through its ActiveJob integration.

### ActiveJob on delayed_job

By default, `ActiveJob::QueueAdapters::DelayedJobAdapter` is listed in `config.rails.skippable_job_adapters`, so ActiveJob jobs running on delayed_job are reported by `sentry-delayed_job`. Rails apps can opt in to the `sentry-rails` ActiveJob integration instead by removing the adapter from that list:

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  # ...
  config.rails.skippable_job_adapters.delete("ActiveJob::QueueAdapters::DelayedJobAdapter")
end
```

Once opted in, `sentry-rails` reports those jobs with delayed_job data: the `delayed_job.queue` and `delayed_job.id` tags and the `Active-Job` context. `sentry-delayed_job` only reports errors raised before an ActiveJob job starts, such as a job class that can no longer be loaded. Plain delayed_job jobs are not affected.
