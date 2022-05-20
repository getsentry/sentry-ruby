<p align="center">
  <a href="https://sentry.io/?utm_source=github&utm_medium=logo" target="_blank">
    <picture>
      <source srcset="https://sentry-brand.storage.googleapis.com/sentry-logo-white.png" media="(prefers-color-scheme: dark)" />
      <source srcset="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" media="(prefers-color-scheme: light), (prefers-color-scheme: no-preference)" />
      <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" alt="Sentry" width="280">
    </picture>
  </a>
</p>

_Bad software is everywhere, and we're tired of it. Sentry is on a mission to help developers write better software faster, so we can get back to enjoying technology. If you want to join us [<kbd>**Check out our open positions**</kbd>](https://sentry.io/careers/)_

Sentry SDK for Ruby
===========

| current version | build | coverage | downloads |
| --- | ----- | -------- | --------- |
| [![Gem Version](https://img.shields.io/gem/v/sentry-ruby?label=sentry-ruby)](https://rubygems.org/gems/sentry-ruby) | [![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-ruby%20Test/badge.svg)](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_ruby_test.yml) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-ruby.svg)](https://rubygems.org/gems/sentry-ruby/) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-rails?label=sentry-rails)](https://rubygems.org/gems/sentry-rails) | [![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-rails%20Test/badge.svg)](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_rails_test.yml) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-rails.svg)](https://rubygems.org/gems/sentry-rails/) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-sidekiq?label=sentry-sidekiq)](https://rubygems.org/gems/sentry-sidekiq) | [![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-sidekiq%20Test/badge.svg)](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_sidekiq_test.yml) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-sidekiq.svg)](https://rubygems.org/gems/sentry-sidekiq/) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-delayed_job?label=sentry-delayed_job)](https://rubygems.org/gems/sentry-delayed_job) | [![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-delayed_job%20Test/badge.svg)](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_delayed_job_test.yml) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-delayed_job.svg)](https://rubygems.org/gems/sentry-delayed_job/) |
| [![Gem Version](https://img.shields.io/gem/v/sentry-resque?label=sentry-resque)](https://rubygems.org/gems/sentry-resque) | [![Build Status](https://github.com/getsentry/sentry-ruby/workflows/sentry-resque%20Test/badge.svg)](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_resque_test.yml) | [![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master) | [![Downloads](https://img.shields.io/gem/dt/sentry-resque.svg)](https://rubygems.org/gems/sentry-resque/) |




## Migrate From sentry-raven

**The old `sentry-raven` client has entered maintenance mode and was moved to [here](https://github.com/getsentry/sentry-ruby/tree/master/sentry-raven).**

If you're using `sentry-raven`, we recommend you to migrate to this new SDK. You can find the benefits of migrating and how to do it in our [migration guide](https://docs.sentry.io/platforms/ruby/migration/).

## Requirements

We test on Ruby 2.4, 2.5, 2.6, 2.7, 3.0, and 3.1 at the latest patchlevel/teeny version. We also support JRuby 9.0.

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

You need to use Sentry.init to initialize and configure your SDK:
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

### [Migration Guide](https://docs.sentry.io/platforms/ruby/migration/)

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
