<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br>
</p>

# Raven-Ruby, the Ruby Client for Sentry

### 🚧 Migrating To The New SDK 🚧

We've released our new Ruby SDK, [sentry-ruby](https://github.com/getsentry/sentry-ruby/tree/master/sentry-ruby). Here are the benefits of migrating to it:

- **Unified Interfaces With Other SDKs:** The design of `sentry-raven` is outdated compared with our modern Sentry SDKs. If you also use other Sentry SDKs, such as Sentry's JavaScript SDK for your frontend application, you'll notice that their interfaces are quite different from the one provided for `sentry-raven`. The new `sentry-ruby` SDK provides a more consistent user experience across all different platforms.

- **Performance Monitoring:** The Sentry Ruby SDK includes [performance monitoring](https://docs.sentry.io/product/performance/), which you can enable if you haven't already as ([discussed here](https://docs.sentry.io/platforms/ruby/performance/)).

- **Future Support:** `sentry-raven` has entered maintenance mode, which means it won't receive any new feature supports or aggressive bug fixes.

- **Better Extensibility:** Unlike `sentry-raven`, `sentry-ruby` is built with extensibility in mind and will allow the community to build extensions for different integrations/features.

If you're interested in the migration, please also read our [migration guide](https://docs.sentry.io/platforms/ruby/migration/) for more information.

---


[![Gem Version](https://img.shields.io/gem/v/sentry-raven.svg)](https://rubygems.org/gems/sentry-raven)
![Build Status](https://github.com/getsentry/raven-ruby/workflows/Test/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-raven.svg)](https://rubygems.org/gems/sentry-raven/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-raven&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-raven&package-manager=bundler&version-scheme=semver)


[Documentation](https://docs.sentry.io/clients/ruby/) | [Bug Tracker](https://github.com/getsentry/raven-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.


## Requirements

We test on Ruby 2.3, 2.4, 2.5, 2.6 and 2.7 at the latest patchlevel/teeny version. We also support JRuby 9.0. Our Rails integration works with Rails 4.2+, including Rails 5 and Rails 6.

## Getting Started

### Install

```ruby
gem "sentry-raven"
```

### Raven only runs when Sentry DSN is set

Raven will capture and send exceptions to the Sentry server whenever its DSN is set. This makes environment-based configuration easy - if you don't want to send errors in a certain environment, just don't set the DSN in that environment!

```bash
# Set your SENTRY_DSN environment variable.
export SENTRY_DSN=http://public@example.com/project-id
```
```ruby
# Or you can configure the client in the code.
Raven.configure do |config|
  config.dsn = 'http://public@example.com/project-id'
end
```

### Raven doesn't report some kinds of data by default

**Raven ignores some exceptions by default** - most of these are related to 404s or controller actions not being found. [For a complete list, see the `IGNORE_DEFAULT` constant](https://github.com/getsentry/sentry-ruby/blob/master/sentry-raven/lib/raven/configuration.rb).

Raven doesn't report POST data or cookies by default. In addition, it will attempt to remove any obviously sensitive data, such as credit card or Social Security numbers. For more information about how Sentry processes your data, [check out the documentation on the `processors` config setting.](https://docs.sentry.io/platforms/ruby/configuration/options/)

### Usage

**If you use Rails, you're already done - no more configuration required!** Check [Integrations](https://docs.sentry.io/platforms/ruby/configuration/integrations/) for more details on other gems Sentry integrates with automatically.

Otherwise, Raven supports two methods of capturing exceptions:

```ruby
Raven.capture do
  # capture any exceptions which happen during execution of this block
  1 / 0
end

begin
  1 / 0
rescue ZeroDivisionError => exception
  Raven.capture_exception(exception)
end
```

### More configuration

You're all set - but there's a few more settings you may want to know about too!

#### async

When an error or message occurs, the notification is immediately sent to Sentry. Raven can be configured to send asynchronously:

```ruby
config.async = lambda { |event|
  Thread.new { Raven.send_event(event) }
}
```

Using a thread to send events will be adequate for truly parallel Ruby platforms such as JRuby, though the benefit on MRI/CRuby will be limited. If the async callback raises an exception, Raven will attempt to send synchronously.

Note that the naive example implementation has a major drawback - it can create an infinite number of threads. We recommend creating a background job, using your background job processor, that will send Sentry notifications in the background.

```ruby
config.async = lambda { |event| SentryJob.perform_later(event) }

class SentryJob < ActiveJob::Base
  queue_as :default

  def perform(event)
    Raven.send_event(event)
  end
end
```

#### transport_failure_callback

If Raven fails to send an event to Sentry for any reason (either the Sentry server has returned a 4XX or 5XX response), this Proc or lambda will be called.

```ruby
config.transport_failure_callback = lambda { |event, error|
  AdminMailer.email_admins("Oh god, it's on fire because #{error.message}!", event).deliver_later
}
```

#### Context

Much of the usefulness of Sentry comes from additional context data with the events. Raven makes this very convenient by providing methods to set thread local context data that is then submitted automatically with all events:

```ruby
Raven.user_context email: 'foo@example.com'

Raven.tags_context interesting: 'yes'

Raven.extra_context additional_info: 'foo'
```

You can also use `tags_context` and `extra_context` to provide scoped information:

```ruby
Raven.tags_context(interesting: 'yes') do
  # the `interesting: 'yes'` tag will only present in the requests sent inside the block
  Raven.capture_exception(exception)
end

Raven.extra_context(additional_info: 'foo') do
  # same as above, the `additional_info` will only present in this request
  Raven.capture_exception(exception)
end
```

For more information, see [Context](https://docs.sentry.io/platforms/ruby/enriching-events/context/).

## More Information

* [Documentation](https://docs.sentry.io/clients/ruby/)
* [Bug Tracker](https://github.com/getsentry/raven-ruby/issues)
* [Forum](https://forum.sentry.io/)
- [Discord](https://discord.gg/ez5KZN7)
