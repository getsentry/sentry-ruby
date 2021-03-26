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
# and mores to come in the future!
```

### Sentry only runs when Sentry DSN is set

Sentry will capture and send exceptions to the Sentry server whenever its DSN is set. This makes environment-based configuration easy - if you don't want to send errors in a certain environment, just don't set the DSN in that environment!

```bash
# Set your SENTRY_DSN environment variable.
export SENTRY_DSN=http://public@example.com/project-id
```
```ruby
# Or you can configure the client in the code.
Sentry.init do |config|
  config.dsn = 'http://public@example.com/project-id'
end
```

### Sentry doesn't report some kinds of data by default

**Sentry ignores some exceptions by default** - most of these are related to 404s parameter parsing errors. [For a complete list, see the `IGNORE_DEFAULT` constant](https://github.com/getsentry/sentry-ruby/blob/master/sentry-ruby/lib/sentry/configuration.rb#L151) and the integration gems' `IGNORE_DEFAULT`, like [`sentry-rails`'s](https://github.com/getsentry/sentry-ruby/blob/master/sentry-rails/lib/sentry/rails/configuration.rb#L12)

Sentry doesn't send personally identifiable information (pii) by default, such as request body, user ip or cookies. If you want those information to be sent, you can use the `send_default_pii` config option:

```ruby
Sentry.init do |config|
  # other configs
  config.send_default_pii = true
end
```

### Performance Monitoring

You can activate performance monitoring by enabling traces sampling:

```ruby
Sentry.init do |config|
  # set a uniform sample rate between 0.0 and 1.0
  config.traces_sample_rate = 0.2

  # or control sampling dynamically
  config.traces_sampler = lambda do |sampling_context|
    # sampling_context[:transaction_context] contains the information about the transaction
    # sampling_context[:parent_sampled] contains the transaction's parent's sample decision
    true # return value can be a boolean or a float between 0.0 and 1.0
  end
end
```

To learn more about performance monitoring, please visit the [official documentation](https://docs.sentry.io/platforms/ruby/performance).

### Usage

`sentry-ruby` has a default integration with `Rack`, so you only need to use the middleware in your application like:

```ruby
require 'sentry-ruby'

Sentry.init do |config|
  config.dsn = 'https://examplePublicKey@o0.ingest.sentry.io/0'

  # To activate performance monitoring, set one of these options.
  # We recommend adjusting the value in production:
  config.traces_sample_rate = 0.5
  # or
  config.traces_sampler = lambda do |context|
    true
  end
end

use Sentry::Rack::CaptureExceptions
```

Otherwise, Sentry you can always use the capture helpers manually

```ruby
Sentry.capture_message("hello world!")

begin
  1 / 0
rescue ZeroDivisionError => exception
  Sentry.capture_exception(exception)
end
```

We also provide integrations with popular frameworks/libraries with the related extensions:

- [sentry-rails](https://github.com/getsentry/sentry-ruby/tree/master/sentry-rails)
- [sentry-sidekiq](https://github.com/getsentry/sentry-ruby/tree/master/sentry-sidekiq)
- [sentry-delayed_job](https://github.com/getsentry/sentry-ruby/tree/master/sentry-delayed_job)

### More configuration

You're all set - but there's a few more settings you may want to know about too!

#### Blocking v.s. Non-blocking

`sentry-ruby` sends events asynchronously by default. The functionality works like this:

1. When the SDK is initialized, a `Sentry::BackgroundWorker` will be initialized too.
2. When an event is passed to `Client#capture_event`, instead of sending it directly with `Client#send_event`, we'll let the worker do it.
3. The worker will have a number of threads. And the one of the idle threads will pick the job and call `Client#send_event`.
  - If all the threads are busy, new jobs will be put into a queue, which has a limit of 30.
  - If the queue size is exceeded, new events will be dropped.

However, if you still prefer to use your own async approach, that's totally fine. If you have `config.async` set, the worker won't initialize a thread pool and won't be used either.

##### About `Sentry::BackgroundWorker`

- The worker is built on top of the [concurrent-ruby](https://github.com/ruby-concurrency/concurrent-ruby) gem's [ThreadPoolExecutor](http://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/ThreadPoolExecutor.html), which is also used by Rails ActiveJob's async adapter. This should minimize the risk of messing up client applications with our own thread pool implementaion.

This functionality also introduces a new `background_worker_threads` config option. It allows you to decide how many threads should the worker hold. By default, the value will be the number of the processors your machine has. For example, if your machine has 4 processors, the value would be 4.

Of course, you can always override the value to fit your use cases, like

```ruby
config.background_worker_threads = 5 # the worker will have 5 threads for sending events
```

You can also disable this new non-blocking behaviour by giving a `0` value:

```ruby
config.background_worker_threads = 0 # all events will be sent synchronously
```

If you want to send a particular event immediately, you can use event hints to do it:

```ruby
Sentry.capture_message("send me now!", hint: { background: false })
```

##### `config.async`

You can also use `config.async` to send events with you own worker:

```ruby
config.async = lambda { |event, hint| SentryJob.perform_later(event, hint) }
```

And if you use `sentry-rails`, you can directly use the job we defined for you:

```ruby
config.async = lambda { |event, hint| Sentry::SendEventJob.perform_later(event, hint) }
```


#### Contexts

In sentry-ruby, every event will inherit their contextual data from the current scope. So you can enrich the event's data by configuring the current scope like:

```ruby
Sentry.configure_scope do |scope|
  scope.set_user(id: 1, email: "test@example.com")

  scope.set_tag(:tag, "foo")
  scope.set_tags(tag_1: "foo", tag_2: "bar")

  scope.set_extra(:order_number, 1234)
  scope.set_extras(order_number: 1234, tickets_count: 4)
end

Sentry.capture_exception(exception) # the event will carry all those information now
```

Or use top-level setters


```ruby
Sentry.set_user(id: 1, email: "test@example.com")
Sentry.set_tags(tag_1: "foo", tag_2: "bar")
Sentry.set_extras(order_number: 1234, tickets_count: 4)
```

Or build up a temporary scope for local information:

```ruby
Sentry.configure_scope do |scope|
  scope.set_tags(tag_1: "foo")
end

Sentry.with_scope do |scope|
  scope.set_tags(tag_1: "bar", tag_2: "baz")

  Sentry.capture_message("message") # this event will have 2 tags: tag_1 => "bar" and tag_2 => "baz"
end

Sentry.capture_message("another message") # this event will have 1 tag: tag_1 => "foo"
```

Of course, you can always assign the information on a per-event basis:

```ruby
Sentry.capture_exception(exception, tags: {foo: "bar"})
```

## Resources

* [![Ruby docs](https://img.shields.io/badge/documentation-sentry.io-green.svg?label=ruby%20docs)](https://docs.sentry.io/platforms/ruby/)
* [![Forum](https://img.shields.io/badge/forum-sentry-green.svg)](https://forum.sentry.io/c/sdks)
* [![Discord Chat](https://img.shields.io/discord/621778831602221064?logo=discord&logoColor=ffffff&color=7389D8)](https://discord.gg/PXa5Apfe7K)  
* [![Stack Overflow](https://img.shields.io/badge/stack%20overflow-sentry-green.svg)](https://stackoverflow.com/questions/tagged/sentry)
* [![Twitter Follow](https://img.shields.io/twitter/follow/getsentry?label=getsentry&style=social)](https://twitter.com/intent/follow?screen_name=getsentry)
