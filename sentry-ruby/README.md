<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br />
</p>

_Bad software is everywhere, and we're tired of it. Sentry is on a mission to help developers write better software faster, so we can get back to enjoying technology. If you want to join us [<kbd>**Check out our open positions**</kbd>](https://sentry.io/careers/)_

Sentry SDK for Ruby
===========

| current version | build | coverage | downloads | semver stability |
| --- | ----- | -------- | --------- | ---------------- |
| [![Gem Version](https://img.shields.io/gem/v/sentry-ruby?label=sentry-ruby)](https://github.com/getsentry/sentry-ruby/blob/master/sentry-ruby/CHANGELOG.md) | ![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-ruby%20Test/badge.svg) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-ruby.svg)](https://rubygems.org/gems/sentry-ruby/) | [![SemVer stability](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-ruby&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-ruby&package-manager=bundler&version-scheme=semver) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-rails?label=sentry-rails)](https://github.com/getsentry/sentry-ruby/blob/master/sentry-rails/CHANGELOG.md) | ![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-rails%20Test/badge.svg) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-rails.svg)](https://rubygems.org/gems/sentry-rails/) | [![SemVer stability](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-rails&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-rails&package-manager=bundler&version-scheme=semver) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-sidekiq?label=sentry-sidekiq)](https://github.com/getsentry/sentry-ruby/blob/master/sentry-sidekiq/CHANGELOG.md) | ![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-sidekiq%20Test/badge.svg) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-sidekiq.svg)](https://rubygems.org/gems/sentry-sidekiq/) | [![SemVer stability](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-sidekiq&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-sidekiq&package-manager=bundler&version-scheme=semver) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-delayed_job?label=sentry-delayed_job)](https://github.com/getsentry/sentry-ruby/blob/master/sentry-delayed_job/CHANGELOG.md) | ![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-delayed_job%20Test/badge.svg) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-delayed_job.svg)](https://rubygems.org/gems/sentry-delayed_job/) | [![SemVer stability](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-delayed_job&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-delayed_job&package-manager=bundler&version-scheme=semver) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-resque?label=sentry-resque)](https://github.com/getsentry/sentry-ruby/blob/master/sentry-resque/CHANGELOG.md) | ![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-resque%20Test/badge.svg) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-resque.svg)](https://rubygems.org/gems/sentry-resque/) | [![SemVer stability](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-resque&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-resque&package-manager=bundler&version-scheme=semver) |




## Migrate From sentry-raven

**The old `sentry-raven` client has entered maintenance mode and was moved to [here](https://github.com/getsentry/sentry-ruby/tree/master/sentry-raven).**

If you're using `sentry-raven`, we recommend you to migrate to this new SDK. You can find the benefits of migrating and how to do it in our [migration guide](https://docs.sentry.io/platforms/ruby/migration/).

## Requirements

We test on Ruby 2.4, 2.5, 2.6, 2.7, and 3.0 at the latest patchlevel/teeny version. We also support JRuby 9.0.

If you use self-hosted Sentry, please also make sure its version is above `20.6.0`.

## Getting Started

### Install

```ruby
gem "sentry-ruby"
```

and depends on the integrations you want to have, you might also want to install these:

```ruby
gem "sentry-rails"
gem "sentry-sidekiq"
gem "sentry-delayed_job"
gem "sentry-resque"
```

### Configuration

You can use `Sentry.init` to initialize and configure your SDK:

```ruby
Sentry.init do |config|
  config.dsn = "MY_DSN"
end

```

To learn more about available configuration options, please visit the [official documentation](https://docs.sentry.io/platforms/ruby/configuration/options/).

### Performance Monitoring

You can activate [performance monitoring](https://docs.sentry.io/platforms/ruby/performance) by enabling traces sampling:

```ruby
Sentry.init do |config|
  # set a uniform sample rate between 0.0 and 1.0
  config.traces_sample_rate = 0.2
  # you can also use traces_sampler for more fine-grained sampling
  # please click the link below to learn more
end
```

To learn more about sampling transactions, please visit the [official documentation](https://docs.sentry.io/platforms/ruby/configuration/sampling/#configuring-the-transaction-sample-rate).

### Integrations

- [Rack](https://docs.sentry.io/platforms/ruby/guides/rack/)
- [Rails](https://docs.sentry.io/platforms/ruby/guides/rails/)
- [Sidekiq](https://docs.sentry.io/platforms/ruby/guides/sidekiq/)
- [DelayedJob](https://docs.sentry.io/platforms/ruby/guides/delayed_job/)
- [Resque](https://docs.sentry.io/platforms/ruby/guides/resque/)

### Enriching Events

- [Add more data to the current scope](https://docs.sentry.io/platforms/ruby/guides/rack/enriching-events/scopes/)
- [Add custom breadcrumbs](https://docs.sentry.io/platforms/ruby/guides/rack/enriching-events/breadcrumbs/)
- [Add contextual data](https://docs.sentry.io/platforms/ruby/guides/rack/enriching-events/context/)
- [Add tags](https://docs.sentry.io/platforms/ruby/guides/rack/enriching-events/tags/)

## Resources

* [![Ruby docs](https://img.shields.io/badge/documentation-sentry.io-green.svg?label=ruby%20docs)](https://docs.sentry.io/platforms/ruby/)
* [![Forum](https://img.shields.io/badge/forum-sentry-green.svg)](https://forum.sentry.io/c/sdks)
* [![Discord Chat](https://img.shields.io/discord/621778831602221064?logo=discord&logoColor=ffffff&color=7389D8)](https://discord.gg/PXa5Apfe7K)  
* [![Stack Overflow](https://img.shields.io/badge/stack%20overflow-sentry-green.svg)](https://stackoverflow.com/questions/tagged/sentry)
* [![Twitter Follow](https://img.shields.io/twitter/follow/getsentry?label=getsentry&style=social)](https://twitter.com/intent/follow?screen_name=getsentry)
