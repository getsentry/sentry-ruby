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

# sentry-resque, the Resque integration for Sentry's Ruby client

---


[![Gem Version](https://img.shields.io/gem/v/sentry-resque.svg)](https://rubygems.org/gems/sentry-resque)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/tests.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-resque.svg)](https://rubygems.org/gems/sentry-resque/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-resque&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-resque&package-manager=bundler&version-scheme=semver)


[Documentation](https://docs.sentry.io/platforms/ruby/guides/resque/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-resque"
```

Then you're all set! `sentry-resque` captures exceptions and starts a `queue.resque` transaction for every job your Resque workers perform.

## Maintenance Mode

`sentry-resque` is in maintenance mode. The integration for plain Resque jobs keeps receiving fixes, but new background job features land in `sentry-rails` through its ActiveJob integration.

### ActiveJob on Resque

By default, `ActiveJob::QueueAdapters::ResqueAdapter` is listed in `config.rails.skippable_job_adapters`, so ActiveJob jobs running on Resque are reported by `sentry-resque`. Rails apps can opt in to the `sentry-rails` ActiveJob integration instead by removing the adapter from that list:

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  # ...
  config.rails.skippable_job_adapters.delete("ActiveJob::QueueAdapters::ResqueAdapter")
end
```

Once opted in, `sentry-rails` reports those jobs with Resque data: the `resque.queue` tag, the `Active-Job` context, and the `messaging.*` span data for the Resque queue. `sentry-resque` only reports errors raised before an ActiveJob job starts, such as a job class that can no longer be loaded. Plain Resque jobs are not affected.
