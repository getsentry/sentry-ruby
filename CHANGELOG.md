## Unreleased

### Bug Fixes

- Allow overwriting of context values [#1724](https://github.com/getsentry/sentry-ruby/pull/1724)
  - Fixes [#1722](https://github.com/getsentry/sentry-ruby/issues/1722)
- Avoid duplicated capturing on the same exception object [#1738](https://github.com/getsentry/sentry-ruby/pull/1738)
  - Fixes [#1731](https://github.com/getsentry/sentry-ruby/issues/1731)


### Refactoring

- Encapsulate extension helpers [#1725](https://github.com/getsentry/sentry-ruby/pull/1725)

## 5.1.0

### Features

- Support for Redis [#1697](https://github.com/getsentry/sentry-ruby/pull/1697)

  **New breadcrumb logger: `redis_logger`**

  When you opt in to the new `redis_logger` breadcrumbs logger:

  ```ruby
  config.breadcrumbs_logger = [:redis_logger]
  ```

  The SDK now records a new `db.redis.command` breadcrumb whenever the Redis client is called. Attributes sent are
  `commands`, an array of each Redis command called with the attributes `command` and `key`, as well as `server`, which is
  the Redis server hostname, port and db number.

  **Redis command spans**

  Calls to Redis are also wrapped in a span called `db.redis.command` and if tracing is enabled will be reported to
  Sentry. The span description will be the command and key. e.g. "SET mykey". For transactions this will be in
  the format `MULTI, SET mykey, INCR counter, EXEC`.

- Sync activerecord, actionview and net-http span names [#1681](https://github.com/getsentry/sentry-ruby/pull/1681)
- Support serializing ActiveRecord job arguments in global id form [#1688](https://github.com/getsentry/sentry-ruby/pull/1688)
- Register Sentry's ErrorSubscriber for Rails 7.0+ apps [#1705](https://github.com/getsentry/sentry-ruby/pull/1705)

  Users can now use the unified interfaces: `Rails.error.handle` or `Rails.error.record` to capture exceptions. See [ActiveSupport::ErrorReporter](https://github.com/rails/rails/blob/main/activesupport/lib/active_support/error_reporter.rb) for more information about this feature.

### Bug Fixes

- Avoid causing NoMethodError for Sentry.* calls when the SDK is not inited [#1713](https://github.com/getsentry/sentry-ruby/pull/1713)
  - Fixes [#1706](https://github.com/getsentry/sentry-ruby/issues/1706)
- Transaction#finish should ignore the parent's sampling decision [#1716](https://github.com/getsentry/sentry-ruby/pull/1716)
  - Fixes [#1712](https://github.com/getsentry/sentry-ruby/issues/1712)
- Skip authorization header when send_default_pii is false [#1717](https://github.com/getsentry/sentry-ruby/pull/1717)
  - Fixes [#1714](https://github.com/getsentry/sentry-ruby/issues/1714)

## 5.0.2

- Respect port info provided in user's DSN [#1702](https://github.com/getsentry/sentry-ruby/pull/1702)
  - Fixes [#1699](https://github.com/getsentry/sentry-ruby/issues/1699)
- Capture transaction tags [#1701](https://github.com/getsentry/sentry-ruby/pull/1701)
- Fix `report_after_job_retries`'s decision logic [#1704](https://github.com/getsentry/sentry-ruby/pull/1704)
  - Fixes [#1698](https://github.com/getsentry/sentry-ruby/issues/1698)

## 5.0.1

- Don't reuse Net::HTTP objects in `HTTPTransport` [#1696](https://github.com/getsentry/sentry-ruby/pull/1696)

## 5.0.0

### Breaking Change - Goodbye `faraday` 👋

**TL;DR: If you are already on version `4.9` and do not use `config.transport.http_adapter` and `config.transport.faraday_builder`, you don't need to change anything.**

This version removes the dependency of [faraday](https://github.com/lostisland/faraday) and replaces related implementation with the `Net::HTTP` standard library.


#### Why?

Since the old `sentry-raven` SDK, we've been using `faraday` as the HTTP client for years (see [HTTPTransport](https://github.com/getsentry/sentry-ruby/blob/4-9/sentry-ruby/lib/sentry/transport/http_transport.rb)). It's an amazing tool that saved us many work and allowed us to focus on SDK features.

But because many users also use `faraday` themselves and have their own version requirements, managing this dependency has become harder over the past few years. Just to list a few related issues:

- [#944](https://github.com/getsentry/sentry-ruby/issues/944)
- [#1424](https://github.com/getsentry/sentry-ruby/issues/1424)
- [#1524](https://github.com/getsentry/sentry-ruby/issues/1524)

And with the release of [faraday 2.0](https://github.com/lostisland/faraday/releases/tag/v2.0.0), we could only imagine it getting even more difficult (which it kind of did, see [#1663](https://github.com/getsentry/sentry-ruby/issues/1663)).

So we think it's time to say goodbye to it with this release.


#### What's changed?


By default, the SDK used `faraday`'s `net_http` adapter, which is also built on top of `Net::HTTP`. So this change shouldn't impact most of the users.

The only noticeable changes are the removal of 2 faraday-specific transport configurations:

- `config.transport.http_adapter`
- `config.transport.faraday_builder`

**If you are already on version `4.9` and do not use those configuration options, it'll be as simple as `bundle update`.**

#### What if I still want to use `faraday` to send my events?

`sentry-ruby` already allows users to set a custom transport class with:

```ruby
Sentry.init do |config|
  config.transport.transport_class = MyTransportClass
end
```

So to use a faraday-based transport, you can:

1. Build a `FaradayTransport` like this:

```rb
require 'sentry/transport/http_transport'
require 'faraday'

class FaradayTransport < Sentry::HTTPTransport
  attr_reader :adapter

  def initialize(*args)
    @adapter = :net_http
    super
  end

  def send_data(data)
    encoding = ""

    if should_compress?(data)
      data = Zlib.gzip(data)
      encoding = GZIP_ENCODING
    end

    response = conn.post @endpoint do |req|
      req.headers['Content-Type'] = CONTENT_TYPE
      req.headers['Content-Encoding'] = encoding
      req.headers['X-Sentry-Auth'] = generate_auth_header
      req.body = data
    end

    if has_rate_limited_header?(response.headers)
      handle_rate_limited_response(response.headers)
    end
  rescue Faraday::Error => e
    error_info = e.message

    if e.response
      if e.response[:status] == 429
        handle_rate_limited_response(e.response[:headers])
      else
        error_info += "\nbody: #{e.response[:body]}"
        error_info += " Error in headers is: #{e.response[:headers]['x-sentry-error']}" if e.response[:headers]['x-sentry-error']
      end
    end

    raise Sentry::ExternalError, error_info
  end

  private

  def set_conn
    server = @dsn.server

    log_debug("Sentry HTTP Transport connecting to #{server}")

    Faraday.new(server, :ssl => ssl_configuration, :proxy => @transport_configuration.proxy) do |builder|
      builder.response :raise_error
      builder.options.merge! faraday_opts
      builder.headers[:user_agent] = "sentry-ruby/#{Sentry::VERSION}"
      builder.adapter(*adapter)
    end
  end

  def faraday_opts
    [:timeout, :open_timeout].each_with_object({}) do |opt, memo|
      memo[opt] = @transport_configuration.public_send(opt) if @transport_configuration.public_send(opt)
    end
  end

  def ssl_configuration
    {
      verify: @transport_configuration.ssl_verification,
      ca_file: @transport_configuration.ssl_ca_file
    }.merge(@transport_configuration.ssl || {})
  end
end
```

2. Set `config.transport.transport = FaradayTransport`


**Please keep in mind that this may not work in the future when the SDK changes its `HTTPTransport` implementation.**

## 4.9.2

### Bug Fixes

- Directly execute ActionCable's action if the SDK is not initialized [#1692](https://github.com/getsentry/sentry-ruby/pull/1692)
  - Fixes [#1691](https://github.com/getsentry/sentry-ruby/issues/1691)

## 4.9.1

### Bug Fixes

- Add workaround for ConnectionStub's missing interface [#1686](https://github.com/getsentry/sentry-ruby/pull/1686)
  - Fixes [#1685](https://github.com/getsentry/sentry-ruby/issues/1685)
- Don't initialize Event objects when they won't be sent [#1687](https://github.com/getsentry/sentry-ruby/pull/1687)
  - Fixes [#1683](https://github.com/getsentry/sentry-ruby/issues/1683)

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
