## Unreleased

### Features

- Support recording exception frame's local variables for requests [#1580](https://github.com/getsentry/sentry-ruby/pull/1580)

  This feature will capture local variables when an exception is raised. And currently, 
    - It only captures the last stack frame's local variables (the one that raises the exception) to minimize performance impact.
    - It's only enabled with the `Sentry::Rack::CaptureExceptions` middleware. So exceptions raised in background jobs and manually captured outside requests won't contain local variables.

  To enable this feature, you need to set `config.capture_exception_frame_locals` to `true`:

  ```rb
  Sentry.init do |config|
    config.capture_exception_frame_locals = true # default is false
  end
  ```

  **Please note that this is an experimental feature and could be further enhanced/removed before the final release.**


### Miscellaneous

- Start Testing Against Rails 7.0 [#1581](https://github.com/getsentry/sentry-ruby/pull/1581)
- Tracing subscribers should be multi-event based [#1587](https://github.com/getsentry/sentry-ruby/pull/1587)

## 4.7.3

- Avoid leaking tracing timestamp to breadcrumbs [#1575](https://github.com/getsentry/sentry-ruby/pull/1575)
- Avoid injecting tracing timestamp to all ActiveSupport instrument events [#1576](https://github.com/getsentry/sentry-ruby/pull/1576)
  - Fixes [#1573](https://github.com/getsentry/sentry-ruby/issues/1574)
- `Hub#capture_message` should check its argument's type [#1577](https://github.com/getsentry/sentry-ruby/pull/1577)
  - Fixes [#1574](https://github.com/getsentry/sentry-ruby/issues/1574)

## 4.7.2

- Change default environment to 'development' [#1565](https://github.com/getsentry/sentry-ruby/pull/1565)
  - Fixes [#1559](https://github.com/getsentry/sentry-ruby/issues/1559)
- Re-position RescuedExceptionInterceptor middleware [#1564](https://github.com/getsentry/sentry-ruby/pull/1564)
  - Fixes [#1563](https://github.com/getsentry/sentry-ruby/issues/1563)

## 4.7.1

### Bug Fixes
- Send events when report_after_job_retries is true and a job is configured with retry: 0 [#1557](https://github.com/getsentry/sentry-ruby/pull/1557)
  - Fixes [#1556](https://github.com/getsentry/sentry-ruby/issues/1556)

## 4.7.0

### Features

- Add `monotonic_active_support_logger` [#1531](https://github.com/getsentry/sentry-ruby/pull/1531)
- Support after-retry reporting to `sentry-sidekiq` [#1532](https://github.com/getsentry/sentry-ruby/pull/1532)
- Generate Security Header Endpoint with `Sentry.csp_report_uri` from dsn [#1507](https://github.com/getsentry/sentry-ruby/pull/1507)
- Allow passing backtrace into `Sentry.capture_message` [#1550](https://github.com/getsentry/sentry-ruby/pull/1550)

### Bug Fixes

- Check sentry-rails before injecting ActiveJob skippable adapters [#1544](https://github.com/getsentry/sentry-ruby/pull/1544)
  - Fixes [#1541](https://github.com/getsentry/sentry-ruby/issues/1541)
- Don't apply Scope's transaction name if it's empty [#1546](https://github.com/getsentry/sentry-ruby/pull/1546)
  - Fixes [#1540](https://github.com/getsentry/sentry-ruby/issues/1540)
- Don't start `Sentry::SendEventJob`'s transaction [#1547](https://github.com/getsentry/sentry-ruby/pull/1547)
  - Fixes [#1539](https://github.com/getsentry/sentry-ruby/issues/1539)
- Don't record breadcrumbs in disabled environments [#1549](https://github.com/getsentry/sentry-ruby/pull/1549)
- Scrub header values with invalid encoding [#1552](https://github.com/getsentry/sentry-ruby/pull/1552)
  - Fixes [#1551](https://github.com/getsentry/sentry-ruby/issues/1551)
- Fix mismatched license info. New SDK gems' gemspecs specified `APACHE-2.0` while their `LICENSE.txt` was `MIT`. Now they both are `MIT`.
  - [#1554](https://github.com/getsentry/sentry-ruby/pull/1554)
  - [#1555](https://github.com/getsentry/sentry-ruby/pull/1555)

## 4.6.5

- SDK should drop the event when any event processor returns nil [#1523](https://github.com/getsentry/sentry-ruby/pull/1523)
- Add severity as `sentry_logger`'s breadcrumb hint [#1527](https://github.com/getsentry/sentry-ruby/pull/1527)
- Refactor `sentry-ruby.rb` and add comments [#1529](https://github.com/getsentry/sentry-ruby/pull/1529)

## 4.6.4

- Extend Rake with a more elegant and reliable way [#1517](https://github.com/getsentry/sentry-ruby/pull/1517)
  - Fixes [#1520](https://github.com/getsentry/sentry-ruby/issues/1520)

## 4.6.3

- Silence some ruby warnings [#1504](https://github.com/getsentry/sentry-ruby/pull/1504)
- Silence method redefined warnings [#1513](https://github.com/getsentry/sentry-ruby/pull/1513)
- Correctly pass arguments to a rake task [#1514](https://github.com/getsentry/sentry-ruby/pull/1514)

## 4.6.2

- Declare `resque` as `sentry-resque`'s dependency [#1503](https://github.com/getsentry/sentry-ruby/pull/1503)
  - Fixes [#1502](https://github.com/getsentry/sentry-ruby/issues/1502)
- Declare `delayed_job` and `sidekiq` as integration gem's dependency [#1506](https://github.com/getsentry/sentry-ruby/pull/1506)
- `DSN#server` shouldn't include path [#1505](https://github.com/getsentry/sentry-ruby/pull/1505)
- Fix `sentry-rails`' `backtrace_cleanup_callback` injection [#1510](https://github.com/getsentry/sentry-ruby/pull/1510)
- Disable background worker when executing rake tasks [#1509](https://github.com/getsentry/sentry-ruby/pull/1509)
  - Fixes [#1508](https://github.com/getsentry/sentry-ruby/issues/1508)

## 4.6.1

- Use `ActiveSupport` Lazy Load Hook to Apply `ActiveJob` Extension [#1494](https://github.com/getsentry/sentry-ruby/pull/1494)
- Fix `Sentry::Utils::RealIP` not filtering trusted proxies when part of IP subnet passed as `IPAddr` to `trusted_proxies`. [#1498](https://github.com/getsentry/sentry-ruby/pull/1498)

## 4.6.0

### Features

- Add `sentry-resque` [#1476](https://github.com/getsentry/sentry-ruby/pull/1476)
- Add tracing support to `sentry-resque` [#1480](https://github.com/getsentry/sentry-ruby/pull/1480)
- Set user to the current scope via sidekiq middleware [#1469](https://github.com/getsentry/sentry-ruby/pull/1469)
- Add tracing support to `sentry-delayed_job` [#1482](https://github.com/getsentry/sentry-ruby/pull/1482)

**IMPORTANT**

If your application processes a large number of background jobs and has tracing enabled, it is recommended to check your `traces_sampler` (or switch to `traces_sampler`) and give the background job operations a smaller rate:

```ruby
Sentry.init do |config|
  config.traces_sampler = lambda do |sampling_context|
    transaction_context = sampling_context[:transaction_context]
    op = transaction_context[:op]

    case op
    when /request/
      # sampling for requests
      0.1
    when /delayed_job/ # or resque
      0.001 # adjust this value
    else
      0.0 # ignore all other transactions
    end
  end
end
```

This is to prevent the background job tracing consumes too much of your transaction quota.

### Bug Fixes

- Force encode request body if it's a string [#1484](https://github.com/getsentry/sentry-ruby/pull/1484)
  - Fixes [#1475](https://github.com/getsentry/sentry-ruby/issues/1475) and [#1303](https://github.com/getsentry/sentry-ruby/issues/1303)

## 4.5.2

### Refactoring

- Remove redundant files [#1477](https://github.com/getsentry/sentry-ruby/pull/1477)

### Bug Fixes

- Disable release detection when SDK is not configured to send events [#1471](https://github.com/getsentry/sentry-ruby/pull/1471)
  - Fixes [#885](https://github.com/getsentry/sentry-ruby/issues/885)

## 4.5.1

### Bug Fixes

- Remove response from breadcrumb and span [#1463](https://github.com/getsentry/sentry-ruby/pull/1463)
  - Fixes the issue mentioned in this [comment](https://github.com/getsentry/sentry-ruby/pull/1199#issuecomment-773069840)
- Correct the timing of loading ActiveJobExtensions [#1464](https://github.com/getsentry/sentry-ruby/pull/1464)
  - Fixes [#1249](https://github.com/getsentry/sentry-ruby/issues/1249)
- Limit breadcrumb's message length [#1465](https://github.com/getsentry/sentry-ruby/pull/1465)

## 4.5.0

### Features

- Implement sentry-trace propagation [#1446](https://github.com/getsentry/sentry-ruby/pull/1446)

The SDK will insert the `sentry-trace` to outgoing requests made with `Net::HTTP`. Its value would look like `d827317d25d5420aa3aa97a0257db998-57757614642bdff5-1`.

If the receiver service also uses Sentry and the SDK supports performance monitoring, its tracing event will be connected with the sender application's.

Example:

<img width="1283" alt="connect sentry trace" src="https://user-images.githubusercontent.com/5079556/118963250-d7b40980-b998-11eb-9de4-598d1b220137.png">

This feature is activated by default. But users can use the new `config.propagate_traces` config option to disable it.

- Add configuration option `skip_rake_integration` [#1453](https://github.com/getsentry/sentry-ruby/pull/1453)

With this new option, users can skip exceptions reported from rake tasks by setting it `true`. Default is `false`.

### Bug Fixes

- Allow toggling background sending on the fly [#1447](https://github.com/getsentry/sentry-ruby/pull/1447)
- Disable background worker for runner mode [#1448](https://github.com/getsentry/sentry-ruby/pull/1448)
  - Fixes [#1324](https://github.com/getsentry/sentry-ruby/issues/1324)
