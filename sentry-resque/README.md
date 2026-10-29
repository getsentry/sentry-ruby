<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
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

`sentry-resque` is in maintenance mode. The integration for plain Resque jobs is preserved and keeps receiving fixes, but new background job features land in `sentry-rails` through its ActiveJob integration.

### ActiveJob on Resque

By default, ActiveJob jobs running on Resque are still reported by `sentry-resque`, exactly as before. Rails apps can opt in to the `sentry-rails` ActiveJob integration instead:

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  # ...
  config.resque.active_job_integration = :rails
end
```

Once opted in, `sentry-rails` reports those jobs and `sentry-resque` enriches them with Resque data: the `resque.queue` tag, the `Active-Job` context, and the `messaging.*` span data for the Resque queue. `sentry-resque` still reports errors raised before the job starts, such as a job class that can no longer be loaded. If `ActiveJob::QueueAdapters::ResqueAdapter` is listed in `config.rails.skippable_job_adapters`, `sentry-resque` keeps reporting those jobs itself. Plain Resque jobs are not affected by this setting.

Errors from ActiveJob jobs on Resque that `retry_on` retries are not reported, regardless of `config.rails.active_job_report_on_retry_error`.
