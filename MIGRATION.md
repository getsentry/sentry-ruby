# Migrating from sentry-raven to sentry-ruby

This is the guide for helping current `sentry-raven` users migrate to the new [`sentry-ruby`](https://github.com/getsentry/sentry-ruby/tree/master/sentry-ruby) SDK.

The `sentry-ruby` gem is still at the beta-testing phase. So if you find any issue when using it, please open an issue, and we'll address the problem ASAP. Also, feel free to join our [discord community](https://discord.gg/ez5KZN7) if you have any questions.


## Benefits

### Unified Interfaces With Other SDKs

The design of `sentry-raven` is outdated compare with other Sentry SDKs. If you also use other sentry SDKs, like `sentry-javascript` for your frontend application, you'll notice that their interfaces are quite different from `sentry-raven`'s. So one of the purposes of the new `sentry-ruby` SDK is to provide a consistent user experience across all different platforms.

### Future Support

The `sentry-raven` SDK has entered maintenance mode, which means it won't receive any new feature supports (like the upcoming [performance monitoring](https://docs.sentry.io/product/performance/) feature) or aggressive bug fixes.

### Better Extensibility

Unlike `sentry-raven`, `sentry-ruby` is built with extensibility in mind and will allow the community to build extensions for different integrations/features.

## Major Changes

### Ruby 2.3 & Rails 4 are not supported anymore

### Integrations were extracted into their own gems

`sentry-ruby` still supports integration with `Rack` by providing a built-in middleware. But for integrations with `Rails`, `sidekiq`, and other libraries, you'll need to install gems for them.

Currently available integrations are:
- [sentry-rails](https://github.com/getsentry/sentry-ruby/tree/master/sentry-rails)
- [sentry-sidekiq](https://github.com/getsentry/sentry-ruby/tree/master/sentry-sidekiq)

We'll also support these in the near future
- delayed_jobs
- resque

### Processors were removed

In `sentry-raven` we have different processor classes for data scrubbing. But in `sentry-ruby` we don't support them anymore (just like other SDKs).

To protect users' sensitive data, `sentry-ruby` added a new config option called `send_default_pii`. When its value is `false` (default), sensitive information like

- user ip
- user cookie 
- request body

will **not** be sent to Sentry.

You can re-enable it by setting:

```ruby
config.send_default_pii = true
```

As for scrubbing sensitive data, please use Sentry's [Advanced Data Scrubbing](https://docs.sentry.io/product/data-management-settings/advanced-datascrubbing/) feature.

### New components & structure

Like other Sentry SDKs, `sentry-ruby` now has a unified structure, which introduced 2 new components: `Hub` and `Scope` ([document](https://docs.sentry.io/platforms/ruby/enriching-events/scopes/)). Most users won't interact with `Hub` directly but will need `Scope` to configure contextual data. See the next paragraph for further information.

### Context interfaces changed

In `sentry-raven`, we provided helpers like `Raven.user_context` for setting contextual data. But in `sentry-ruby`, those helpers were removed, and you'll need to use a different approach for setting those data like:


#### Configure data globally

```ruby
# Before
Raven.user_context(id: 1)

# After
Sentry.configure_scope do |scope|
  scope.set_user(id: 1)
end
```

#### Configure data in a local scope

```ruby
# Before
Raven.tag_context(foo: "bar") do
  Raven.capture_message("test")
end

# After
Sentry.configure_scope do |scope|
  scope.set_user(id: 1)
  
  Sentry.capture_message("test")
end
```

## Examples

This section will use code examples to guide you through the changes required for the migration.

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
Sentry.configure_scope do |scope|
  scope.set_uer(id: 1)
  scope.set_tags(foo: "bar")
  scope.set_extra(debug: true)
end
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
Sentry.with_scope do |scope|
  scope.set_user(id: 1)
  scope.set_tags(foo: "bar")
  scope.set_extra(debug: true)
  # send event
end
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

**Configuration Options**

Removed: 
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
```

Renamed/Relocated:

```ruby
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

Added:

```ruby
# this behaves similar to the old config.scheme option
config.transport.transport_class = MyTransportClass
```
