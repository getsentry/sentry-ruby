## Unreleased

### Features

- Sync activerecord, actionview and net-http span names [#1681](https://github.com/getsentry/sentry-ruby/pull/1681)

## 4.9.0

### Features

- Add Action Cable exception capturing (Rails 6+) [#1638](https://github.com/getsentry/sentry-ruby/pull/1638)
- Add request body & query string to `Net::HTTP` breadcrumb [#1637](https://github.com/getsentry/sentry-ruby/pull/1637)

When `config.send_default_pii` is set as `true`, `:http_logger` will include query string and request body in the breadcrumbs it logs.

- Add tracing support to `ActionCable` integration [#1640](https://github.com/getsentry/sentry-ruby/pull/1640)

### Bug Fixes

- Fix `Net::HTTP` breadcrump url when using `Net::HTTP.new` [#1637](https://github.com/getsentry/sentry-ruby/pull/1637)
- Fix trace span creation when using `Net::HTTP.start` [#1637](https://github.com/getsentry/sentry-ruby/pull/1637)
- Remove incorrect backtrace attribute from Event [#1672](https://github.com/getsentry/sentry-ruby/pull/1672)

### Documentation

- Document Transaction and Span classes [#1653](https://github.com/getsentry/sentry-ruby/pull/1653)
- Document Client and Scope classes [#1659](https://github.com/getsentry/sentry-ruby/pull/1659)
- Document Event and interface classes [#1675](https://github.com/getsentry/sentry-ruby/pull/1675)
- Document TransactionEvent and breadcrumb-related classes [#1676](https://github.com/getsentry/sentry-ruby/pull/1676)
- Use macro to avoid duplicated documentation [#1677](https://github.com/getsentry/sentry-ruby/pull/1677)

### Refactoring

- Minor improvements on Net::HTTP patch [#1651](https://github.com/getsentry/sentry-ruby/pull/1651)
- Deprecate unnecessarily exposed attributes [#1652](https://github.com/getsentry/sentry-ruby/pull/1652)
- Refactor Net::HTTP patch [#1656](https://github.com/getsentry/sentry-ruby/pull/1656)
- Deprecate Event#configuration [#1661](https://github.com/getsentry/sentry-ruby/pull/1661)
- Explicitly passing Rack related configurations [#1662](https://github.com/getsentry/sentry-ruby/pull/1662)
- Refactor RequestInterface [#1673](https://github.com/getsentry/sentry-ruby/pull/1673)

## 4.8.3

### Bug Fixes

- Correctly return `JobClass#perform`'s return value [#1667](https://github.com/getsentry/sentry-ruby/pull/1667)
  - Fixes [#1666](https://github.com/getsentry/sentry-ruby/issues/1666)

## 4.8.2

### Documentation

- Rewrite documents with yard [#1635](https://github.com/getsentry/sentry-ruby/pull/1635)

### Bug Fixes

- Use prepended method instead of `around_perform` for `ActiveJob` integration [#1631](https://github.com/getsentry/sentry-ruby/pull/1631)
  - Fixes [#956](https://github.com/getsentry/sentry-ruby/issues/956) and [#1629](https://github.com/getsentry/sentry-ruby/issues/1629)
- Remove unnecessary ActiveJob inclusion [#1655](https://github.com/getsentry/sentry-ruby/pull/1655)
- Lock faraday to version 1.x [#1664](https://github.com/getsentry/sentry-ruby/pull/1664)
  - This is a temporary effort to avoid dependency issue with `faraday 2.0` and `faraday` will be removed from dependencies very soon. 
    See [this comment](https://github.com/getsentry/sentry-ruby/issues/1663) for more information about our plan to remove it.

## 4.8.1

### Bug Fixes

- Merge context with the same key instead of replacing the old value. [#1621](https://github.com/getsentry/sentry-ruby/pull/1621)
  - Fixes [#1619](https://github.com/getsentry/sentry-ruby/issues/1619)
- Fix `HTTPTransport`'s `ssl` configuration [#1626](https://github.com/getsentry/sentry-ruby/pull/1626)
- Log errors happened in `BackgroundWorker#perform` [#1624](https://github.com/getsentry/sentry-ruby/pull/1624)
  - Fixes [#1618](https://github.com/getsentry/sentry-ruby/issues/1618)
- Gracefully shutdown background worker before the process exits [#1617](https://github.com/getsentry/sentry-ruby/pull/1617)
  - Fixes [#1612](https://github.com/getsentry/sentry-ruby/issues/1612)

### Refactoring

- Extract envelope construction logic from Transport [#1616](https://github.com/getsentry/sentry-ruby/pull/1616)
- Add frozen string literal comment to sentry-ruby [#1623](https://github.com/getsentry/sentry-ruby/pull/1623)

## 4.8.0

### Features

- Support exception frame's local variable capturing
  - [#1580](https://github.com/getsentry/sentry-ruby/pull/1580)
  - [#1589](https://github.com/getsentry/sentry-ruby/pull/1589)

  **Example**:

  <img width="80%" alt="locals capturing" src="https://user-images.githubusercontent.com/5079556/134694936-8c42ca09-870a-4587-b1ff-e8ddd79d2ce7.png">

  To enable this feature, you need to set `config.capture_exception_frame_locals` to `true`:

  ```rb
  Sentry.init do |config|
    config.capture_exception_frame_locals = true # default is false
  end
  ```

  This feature should only introduce negligible performance overhead in most Ruby applications. But if you notice obvious performance regression, please file an issue and we'll investigate it.

- Support `ActiveStorage` spans in tracing events [#1588](https://github.com/getsentry/sentry-ruby/pull/1588)
- Support `Sidekiq` Tags in Sentry [#1596](https://github.com/getsentry/sentry-ruby/pull/1596)
- Add Client Reports to collect dropped event statistics [#1604](https://github.com/getsentry/sentry-ruby/pull/1604)

  This feature reports statistics about dropped events along with sent events (so no additional requests made). It'll help Sentry improve SDKs and features like rate-limiting. This information will not be visible to users at the moment, but we're planning to add this information to user-facing UI.

  If you **don't** want to send this data, you can opt-out by setting `config.send_client_reports = false`.

### Bug Fixes

- Connect `Sidekiq`'s transaction with its parent when possible [#1590](https://github.com/getsentry/sentry-ruby/pull/1590)
  - Fixes [#1586](https://github.com/getsentry/sentry-ruby/issues/1586)
- Use nil instead of false to disable callable settings [#1594](https://github.com/getsentry/sentry-ruby/pull/1594)
- Avoid duplicated sampling on Transaction events [#1601](https://github.com/getsentry/sentry-ruby/pull/1601)
- Remove verbose data from `#inspect` result [#1602](https://github.com/getsentry/sentry-ruby/pull/1602)

### Refactoring

- Move Sentry::Rails::CaptureExceptions before ActionDispatch::ShowExceptions [#1608](https://github.com/getsentry/sentry-ruby/pull/1608)
- Refactor `Sentry::Configuration` [#1595](https://github.com/getsentry/sentry-ruby/pull/1595)
- Tracing subscribers should be multi-event based [#1587](https://github.com/getsentry/sentry-ruby/pull/1587)

### Miscellaneous

- Start Testing Against Rails 7.0 [#1581](https://github.com/getsentry/sentry-ruby/pull/1581)


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
