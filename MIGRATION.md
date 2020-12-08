# Migrating from sentry-raven to sentry-ruby

This is the guide for helping current `sentry-raven` users migrate to the new [`sentry-ruby`](https://github.com/getsentry/sentry-ruby/tree/master/sentry-ruby) SDK.

The `sentry-ruby` gem is still at the beta-testing phase. So if you find any issue when using it, please open an issue, and we'll address the problem ASAP. Also, feel free to join our [discord community](https://discord.gg/ez5KZN7) if you have any questions.

## Table of Content

- [Benefits](#benefits)
- [Major Changes](#major-changes)
- [Configuration Changes](#configuration-changes)
- [API Changes](#api-changes)
- [Example Apps](#example-apps)

## Benefits

- **Unified Interfaces With Other SDKs:** The design of `sentry-raven` is outdated compared with our modern Sentry SDKs. If you also use other Sentry SDKs, such as Sentry's JavaScript SDK for your frontend application, you'll notice that their interfaces are quite different from the one provided for `sentry-raven`. The new `sentry-ruby` SDK provides a more consistent user experience across all different platforms.

- **Performance Monitoring:** The Sentry Ruby SDK includes [performance monitoring](https://docs.sentry.io/product/performance/), which you can enable if you haven't already as ([discussed here](https://docs.sentry.io/platforms/ruby/performance/)). 

- **Future Support:** `sentry-raven` has entered maintenance mode, which means it won't receive any new feature supports or aggressive bug fixes.

- **Better Extensibility:** Unlike `sentry-raven`, `sentry-ruby` is built with extensibility in mind and will allow the community to build extensions for different integrations/features.

## Major Changes

### Ruby 2.3 and Rails 4 are no longer supported.

#### Integrations Were Extracted

Sentry's Ruby SDK still supports integration with `Rack` by providing built-in middleware, but you'll need to install gems for integrations with `Rails`, `sidekiq`, and other libraries.

Currently available integrations are:
- [sentry-rails](https://github.com/getsentry/sentry-ruby/tree/master/sentry-rails)
- [sentry-sidekiq](https://github.com/getsentry/sentry-ruby/tree/master/sentry-sidekiq)

We'll also support these in the near future:
- delayed_jobs
- resque

#### Processors Were Removed

In `sentry-raven` we have different processor classes for data scrubbing. But updated Sentry Ruby SDK doesn't support these processors. Instead, to protect users' sensitive data, the Ruby SDK adds a new configuration option of `send_default_pii`. When the value is set to `false` (default), sensitive information, such as
- user ip
- user cookie
- request body

will **not** be sent to Sentry.

You can re-enable it by setting:

```ruby
config.send_default_pii = true
```

As for scrubbing sensitive data, please use Sentry's [Advanced Data Scrubbing](https://docs.sentry.io/product/data-management-settings/advanced-datascrubbing/) feature.

#### New Components and Structure

Sentry's Ruby SDK uses a unified structure, which introduces two new components: `Hub` and `Scope` ([which are both documented here](https://docs.sentry.io/platforms/ruby/enriching-events/scopes/)). Most users won't interact with `Hub` directly, but will need `Scope` to configure contextual data.

#### Context Interfaces Changed

In `sentry-raven`, we provided helpers like `Raven.user_context` for setting contextual data. But in `sentry-ruby`, those helpers were removed, and you'll need to use a different approach for setting those data like:


Configure data globally

```ruby
# Before
Raven.user_context(id: 1)

# After
Sentry.set_user(id: 1)
```

Configure data in a local scope

```ruby
# Before
Raven.tag_context(foo: "bar") do
  Raven.capture_message("test")
end

# After
Sentry.with_scope do |scope|
  scope.set_user(id: 1)

  Sentry.capture_message("test")
end
```

## Configuration Changes

#### Removed

```ruby
config.sanitize_credit_cards
config.sanitize_fields
config.sanitize_fields_excluded
config.sanitize_http_headers

config.scheme
config.secret_key
config.server

config.tags
config.logger
config.encoding

# please only use config.before_send
config.should_capture
config.transport_failure_callback
```

#### Renamed/Relocated

```ruby
config.current_environment #=> config.environment
config.environments #=> config.enabled_environments

config.rails_report_rescued_exceptions #=> config.rails.report_rescued_exceptions with sentry-rails installed

config.ssl #=> config.transport.ssl
config.ssl_ca_file #=> config.transport.ssl_ca_file
config.ssl_verification #=> config.transport.ssl_verification
config.timeout #=> config.transport.timeout
config.open_timeout #=> config.transport.open_timeout
config.proxy #=> config.transport.proxy
config.http_adapter #=> config.transport.http_adapter
config.faraday_builder #=> config.transport.faraday_builder
```

#### Added

```ruby
# this behaves similar to the old config.scheme option
config.transport.transport_class = MyTransportClass
```

## API Changes

In this section, we provide code examples to guide you through the changes required for the migration.

**Installation**

Old:

```ruby
gem "sentry-raven"
```

New:

```ruby
gem "sentry-ruby"

# and the integrations you need
gem "sentry-rails"
gem "sentry-sidekiq"
```

**Configuration**

Old:

```ruby
Raven.configure do |config|
  config.dsn = "DSN"
end
```

New:

```ruby
Sentry.init do |config|
  config.dsn = "DSN"
end
```

**Set Contextual Data (global)**

Old:

```ruby
Raven.user_context(id: 1)
Raven.context.tags = { foo: "bar" }
Raven.context.extra = { debug: true }
```

New:

```ruby
Sentry.set_user(id: 1)
Sentry.set_tags(foo: "bar")
Sentry.set_extras(debug: true)
```

**Set Contextual Data (local)**

Old:

```ruby
Raven.user_context(id: 1) do
  # send event
end
Raven.tag_context(foo: "bar") do
  # send event
end
Raven.extra_context(debug: true) do
  # send event
end
```

New:

```ruby
Sentry.set_user(id: 1)
Sentry.set_tags(foo: "bar")
Sentry.set_extras(debug: true)
# send event
```


**Manual Message/Exception Capturing**

Old:

```ruby
Raven.capture_message("test", extra: { debug: true })
```

New:

```ruby
Sentry.capture_message("test", extra: { debug: true })
```

## Example Apps

- [Rails example](https://github.com/getsentry/sentry-ruby/tree/master/sentry-rails/examples/rails-6.0)
- [Sinatra example](https://github.com/getsentry/sentry-ruby/tree/master/sentry-ruby/examples/sinatra)
- Sidekiq examples:
  - [with Rails](https://github.com/getsentry/sentry-ruby/tree/master/sentry-rails/examples/rails-6.0)
  - [without Rails](https://github.com/getsentry/sentry-ruby/tree/master/sentry-sidekiq/example)

