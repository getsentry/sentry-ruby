## Unreleased

### Features

- Add support for $SENTRY_DEBUG and $SENTRY_SPOTLIGHT ([#2374](https://github.com/getsentry/sentry-ruby/pull/2374))
- Support human readable intervals in `sidekiq-cron` ([#2387](https://github.com/getsentry/sentry-ruby/pull/2387))

## 5.19.0

### Features

- Use `Concurrent.available_processor_count` instead of `Concurrent.usable_processor_count` ([#2358](https://github.com/getsentry/sentry-ruby/pull/2358))

- Support for tracing Faraday requests ([#2345](https://github.com/getsentry/sentry-ruby/pull/2345))
  - Closes [#1795](https://github.com/getsentry/sentry-ruby/issues/1795)
  - Please note that the Faraday instrumentation has some limitations in case of async requests: <https://github.com/lostisland/faraday/issues/1381>

  Usage:

  ```rb
  Sentry.init do |config|
    # ...
    config.enabled_patches << :faraday
  end
  ```

- Support for attachments ([#2357](https://github.com/getsentry/sentry-ruby/pull/2357))

  Usage:

  ```ruby
  Sentry.add_attachment(path: '/foo/bar.txt')
  Sentry.add_attachment(filename: 'payload.json', bytes: '{"value": 42}'))
  ```

- Transaction data are now included in the context ([#2365](https://github.com/getsentry/sentry-ruby/pull/2365))
  - Closes [#2363](https://github.com/getsentry/sentry-ruby/issues/2363)

- Inject Sentry meta tags in the Rails application layout automatically in the generator ([#2369](https://github.com/getsentry/sentry-ruby/pull/2369))

  To turn this behavior off, use

  ```bash
  bin/rails generate sentry --inject-meta false
  ```

### Bug Fixes

- Fix skipping `connect` spans in open-telemetry [#2364](https://github.com/getsentry/sentry-ruby/pull/2364)

## 5.18.2

### Bug Fixes

- Don't overwrite `ip_address` if already set on `user` [#2350](https://github.com/getsentry/sentry-ruby/pull/2350)
  - Fixes [#2347](https://github.com/getsentry/sentry-ruby/issues/2347)
- `teardown_sentry_test` helper should clear global even processors too ([#2342](https://github.com/getsentry/sentry-ruby/pull/2342))
- Suppress the unnecessary “unsupported options notice” ([#2349](https://github.com/getsentry/sentry-ruby/pull/2349))

### Internal

- Use `Concurrent.usable_processor_count` when it is available ([#2339](https://github.com/getsentry/sentry-ruby/pull/2339))
- Report dropped spans in Client Reports ([#2346](https://github.com/getsentry/sentry-ruby/pull/2346))

## 5.18.1

### Bug Fixes

- Drop `Gem::Specification`'s usage so it doesn't break bundler standalone ([#2335](https://github.com/getsentry/sentry-ruby/pull/2335))

## 5.18.0

### Features

- Add generator for initializer generation ([#2286](https://github.com/getsentry/sentry-ruby/pull/2286))

  Rails users will be able to use `bin/rails generate sentry` to generate their `config/initializers/sentry.rb` file.

- Notify users when their custom options are discarded ([#2303](https://github.com/getsentry/sentry-ruby/pull/2303))
- Add a new `:graphql` patch to automatically enable instrumenting GraphQL spans ([#2308](https://github.com/getsentry/sentry-ruby/pull/2308))

    Usage:

    ```rb
    Sentry.init do |config|
      # ...
      config.enabled_patches += [:graphql]
    end
    ```

- Add `Sentry.get_trace_propagation_meta` helper for injecting meta tags into views ([#2314](https://github.com/getsentry/sentry-ruby/pull/2314))
- Add query source support to `sentry-rails` ([#2313](https://github.com/getsentry/sentry-ruby/pull/2313))

  The feature is only activated in apps that use Ruby 3.2+ and Rails 7.1+. By default only queries that take longer than 100ms will have source recorded, which can be adjusted by updating the value of `config.rails.db_query_source_threshold_ms`.
- Log envelope delivery message with debug instead of info ([#2320](https://github.com/getsentry/sentry-ruby/pull/2320))

### Bug Fixes

- Don't throw error on arbitrary arguments being passed to `capture_event` options [#2301](https://github.com/getsentry/sentry-ruby/pull/2301)
  - Fixes [#2299](https://github.com/getsentry/sentry-ruby/issues/2299)
- Decrease the default number of background worker threads by half ([#2305](https://github.com/getsentry/sentry-ruby/pull/2305))
  - Fixes [#2297](https://github.com/getsentry/sentry-ruby/issues/2297)
- Don't mutate `enabled_environments` when using `Sentry::TestHelper` ([#2317](https://github.com/getsentry/sentry-ruby/pull/2317))
- Don't use array for transaction names and sources on scope ([#2324](https://github.com/getsentry/sentry-ruby/pull/2324))
  - Fixes [#2257](https://github.com/getsentry/sentry-ruby/issues/2257)
  - **BREAKING** This removes the internal `scope.transaction_names` method, please use `scope.transaction_name` instead

### Internal

- Add `origin` to spans and transactions to track integration sources for instrumentation ([#2319](https://github.com/getsentry/sentry-ruby/pull/2319))

## 5.17.3

### Internal

- Update key, unit and tags sanitization logic for metrics [#2292](https://github.com/getsentry/sentry-ruby/pull/2292)
- Consolidate client report and rate limit handling with data categories [#2294](https://github.com/getsentry/sentry-ruby/pull/2294)
- Record `:network_error` client reports for `send_envelope` [#2295](https://github.com/getsentry/sentry-ruby/pull/2295)

### Bug Fixes

- Make sure isolated envelopes respect `config.enabled_environments` [#2291](https://github.com/getsentry/sentry-ruby/pull/2291)
  - Fixes [#2287](https://github.com/getsentry/sentry-ruby/issues/2287)

## 5.17.2

### Internal

- Add `Mechanism` interface and default to unhandled for integration exceptions [#2280](https://github.com/getsentry/sentry-ruby/pull/2280)

### Bug Fixes

- Don't instantiate connection in `ActiveRecordSubscriber` ([#2278](https://github.com/getsentry/sentry-ruby/pull/2278))

## 5.17.1

### Bug Fixes

- Fix NoMethodError / Make session_tracking check consistent ([#2269](https://github.com/getsentry/sentry-ruby/pull/2269))

## 5.17.0

### Features

- Add support for distributed tracing in `sentry-delayed_job` [#2233](https://github.com/getsentry/sentry-ruby/pull/2233)
- Fix warning about default gems on Ruby 3.3.0 ([#2225](https://github.com/getsentry/sentry-ruby/pull/2225))
- Add `hint:` support to `Sentry::Rails::ErrorSubscriber` [#2235](https://github.com/getsentry/sentry-ruby/pull/2235)
- Add [Metrics](https://docs.sentry.io/product/metrics/) support
  - Add main APIs and `Aggregator` thread [#2247](https://github.com/getsentry/sentry-ruby/pull/2247)
  - Add `Sentry::Metrics.timing` API for measuring block duration [#2254](https://github.com/getsentry/sentry-ruby/pull/2254)
  - Add metric summaries on spans [#2255](https://github.com/getsentry/sentry-ruby/pull/2255)
  - Add `config.metrics.before_emit` callback [#2258](https://github.com/getsentry/sentry-ruby/pull/2258)
  - Add code locations for metrics [#2263](https://github.com/getsentry/sentry-ruby/pull/2263)

    The SDK now supports recording and aggregating metrics. A new thread will be started
    for aggregation and will flush the pending data to Sentry every 5 seconds.

    To enable this behavior, use:

    ```ruby
    Sentry.init do |config|
      # ...
      config.metrics.enabled = true
    end
    ```

    And then in your application code, collect metrics as follows:

    ```ruby
    # increment a simple counter
    Sentry::Metrics.increment('button_click')
    # set a value, unit and tags
    Sentry::Metrics.increment('time', 5, unit: 'second', tags: { browser:' firefox' })

    # distribution - get statistical aggregates from an array of observations
    Sentry::Metrics.distribution('page_load', 15.0, unit: 'millisecond')

    # gauge - record statistical aggregates directly on the SDK, more space efficient
    Sentry::Metrics.gauge('page_load', 15.0, unit: 'millisecond')

    # set - get unique counts of elements
    Sentry::Metrics.set('user_view', 'jane')

    # timing - measure duration of code block, defaults to seconds
    # will also automatically create a `metric.timing` span
    Sentry::Metrics.timing('how_long') { sleep(1) }
    # timing - measure duration of code block in other duraton units
    Sentry::Metrics.timing('how_long_ms', unit: 'millisecond') { sleep(0.5) }
    ```

    You can filter some keys or update tags on the fly with the `before_emit` callback, which will be triggered before a metric is aggregated.

    ```ruby
    Sentry.init do |config|
      # ...
      # the 'foo' metric will be filtered and the tags will be updated to add :bar and remove :baz
      config.metrics.before_emit = lambda do |key, tags|
        return nil if key == 'foo'
        tags[:bar] = 42
        tags.delete(:baz)
        true
      end
    end
    ```

    By default, the SDK will send code locations for unique metrics (defined by type, key and unit) once a day and with every startup/shutdown of your application.
    You can turn this off with the following:

    ```ruby
    Sentry.init do |config|
      # ...
      config.metrics.enable_code_locations = false
    end
    ```

### Bug Fixes

- Fix undefined method 'constantize' issue in `sentry-resque` ([#2248](https://github.com/getsentry/sentry-ruby/pull/2248))
- Only instantiate SessionFlusher when the SDK is enabled under the current env [#2245](https://github.com/getsentry/sentry-ruby/pull/2245)
  - Fixes [#2234](https://github.com/getsentry/sentry-ruby/issues/2234)
- Update backtrace parsing regexp to support Ruby 3.4 ([#2252](https://github.com/getsentry/sentry-ruby/pull/2252))
- Make sure ``sending_allowed?`` is respected irrespective of spotlight configuration ([#2231](https://github.com/getsentry/sentry-ruby/pull/2231))
  - Fixes [#2226](https://github.com/getsentry/sentry-ruby/issues/2226)

## 5.16.1

### Bug Fixes

- Pin `sqlite3` gem for building because of failed release [#2222](https://github.com/getsentry/sentry-ruby/pull/2222)

## 5.16.0

### Features

- Add backpressure handling for transactions [#2185](https://github.com/getsentry/sentry-ruby/pull/2185)

    The SDK can now dynamically downsample transactions to reduce backpressure in high
    throughput systems. It starts a new `BackpressureMonitor` thread to perform some health checks
    which decide to downsample (halved each time) in 10 second intervals till the system
    is healthy again.

    To enable this behavior, use:

    ```ruby
    Sentry.init do |config|
      # ...
      config.traces_sample_rate = 1.0
      config.enable_backpressure_handling = true
    end
    ```

    If your system serves heavy load, please let us know how this feature works for you!

- Implement proper flushing logic on ``close`` for Client Reports and Sessions [#2206](https://github.com/getsentry/sentry-ruby/pull/2206)
- Support cron with timezone for `sidekiq-scheduler` patch [#2209](https://github.com/getsentry/sentry-ruby/pull/2209)
  - Fixes [#2187](https://github.com/getsentry/sentry-ruby/issues/2187)
- Add `Cron::Configuration` object that holds defaults for all ``MonitorConfig`` objects [#2211](https://github.com/getsentry/sentry-ruby/pull/2211)

    ```ruby
    Sentry.init do |config|
      # ...
      config.cron.default_checkin_margin = 1
      config.cron.default_max_runtime = 30
      config.cron.default_timezone = 'America/New_York'
    end
    ```

- Clean up logging [#2216](https://github.com/getsentry/sentry-ruby/pull/2216)
- Pick up config.cron.default_timezone from Rails config [#2213](https://github.com/getsentry/sentry-ruby/pull/2213)
- Don't add most scope data (tags/extra/breadcrumbs) to `CheckInEvent` [#2217](https://github.com/getsentry/sentry-ruby/pull/2217)

## 5.15.2

### Bug Fixes

- Fix `sample_rate` applying to check-in events [#2203](https://github.com/getsentry/sentry-ruby/pull/2203)
  - Fixes [#2202](https://github.com/getsentry/sentry-ruby/issues/2202)

## 5.15.1

### Features

- Expose `configuration.background_worker_max_queue` to control thread pool queue size [#2195](https://github.com/getsentry/sentry-ruby/pull/2195)

### Bug Fixes

- Fix `Sentry::Cron::MonitorCheckIns` monkeypatch keyword arguments [#2199](https://github.com/getsentry/sentry-ruby/pull/2199)
  - Fixes [#2198](https://github.com/getsentry/sentry-ruby/issues/2198)

## 5.15.0

### Features

- You can now use [Spotlight](https://spotlightjs.com) with your apps that use sentry-ruby! [#2175](https://github.com/getsentry/sentry-ruby/pull/2175)
- Improve default slug generation for `sidekiq-scheduler` [#2184](https://github.com/getsentry/sentry-ruby/pull/2184)

### Bug Fixes

- Network errors raised in `Sentry::HTTPTransport` will no longer be reported to Sentry [#2178](https://github.com/getsentry/sentry-ruby/pull/2178)

## 5.14.0

### Features

- Improve default slug generation for Crons [#2168](https://github.com/getsentry/sentry-ruby/pull/2168)
- Change release name generator to use full SHA commit hash and align with `sentry-cli` and other Sentry SDKs [#2174](https://github.com/getsentry/sentry-ruby/pull/2174)
- Automatic Crons support for scheduling gems
  - Add support for [`sidekiq-cron`](https://github.com/sidekiq-cron/sidekiq-cron) [#2170](https://github.com/getsentry/sentry-ruby/pull/2170)

    You can opt in to the `sidekiq-cron` patch and we will automatically monitor check-ins for all jobs listed in your `config/schedule.yml` file.

    ```rb
    config.enabled_patches += [:sidekiq_cron]
    ```

  - Add support for [`sidekiq-scheduler`](https://github.com/sidekiq-scheduler/sidekiq-scheduler) [#2172](https://github.com/getsentry/sentry-ruby/pull/2172)

    You can opt in to the `sidekiq-scheduler` patch and we will automatically monitor check-ins for all repeating jobs (i.e. `cron`, `every`, and `interval`) specified in the config.

    ```rb
    config.enabled_patches += [:sidekiq_scheduler]
    ```

### Bug Fixes

- Fixed a deprecation in `sidekiq-ruby` error handler [#2160](https://github.com/getsentry/sentry-ruby/pull/2160)
- Avoid invoking ActiveSupport::BroadcastLogger if not defined [#2169](https://github.com/getsentry/sentry-ruby/pull/2169)
- Respect custom `Delayed::Job.max_attempts` if it's defined [#2176](https://github.com/getsentry/sentry-ruby/pull/2176)
- Fixed a bug where `Net::HTTP` instrumentation won't work for some IPv6 addresses [#2180](https://github.com/getsentry/sentry-ruby/pull/2180)
- Allow non-string error message to be reported to sentry ([#2137](https://github.com/getsentry/sentry-ruby/pull/2137))

## 5.13.0

### Features

- Make additional job context available to traces_sampler for determining sample rate (sentry-delayed_job) [#2148](https://github.com/getsentry/sentry-ruby/pull/2148)
- Add new `config.rails.active_support_logger_subscription_items` to allow customization breadcrumb data of active support logger [#2139](https://github.com/getsentry/sentry-ruby/pull/2139)

  ```rb
    config.rails.active_support_logger_subscription_items["sql.active_record"] << :type_casted_binds
    config.rails.active_support_logger_subscription_items.delete("sql.active_record")
    config.rails.active_support_logger_subscription_items["foo"] = :bar
  ```

- Enable opting out of patches [#2151](https://github.com/getsentry/sentry-ruby/pull/2151)

### Bug Fixes

- Fix puma integration for versions before v5 [#2141](https://github.com/getsentry/sentry-ruby/pull/2141)
- Fix breadcrumbs with `warn` level not being ingested [#2150](https://github.com/getsentry/sentry-ruby/pull/2150)
  - Fixes [#2145](https://github.com/getsentry/sentry-ruby/issues/2145)
- Don't send negative line numbers in profiles [#2158](https://github.com/getsentry/sentry-ruby/pull/2158)
- Allow transport proxy configuration to be set with `HTTP_PROXY` environment variable [#2161](https://github.com/getsentry/sentry-ruby/pull/2161)

## 5.12.0

### Features

- Record client reports for profiles [#2107](https://github.com/getsentry/sentry-ruby/pull/2107)
- Adopt Rails 7.1's new BroadcastLogger [#2120](https://github.com/getsentry/sentry-ruby/pull/2120)
- Support sending events after all retries were performed (sentry-resque) [#2087](https://github.com/getsentry/sentry-ruby/pull/2087)
- Add [Cron Monitoring](https://docs.sentry.io/product/crons/) support
  - Add `Sentry.capture_check_in` API for Cron Monitoring [#2117](https://github.com/getsentry/sentry-ruby/pull/2117)

    You can now track progress of long running scheduled jobs.

    ```rb
    check_in_id = Sentry.capture_check_in('job_name', :in_progress)
    # do job stuff
    Sentry.capture_check_in('job_name', :ok, check_in_id: check_in_id)
    ```

  - Add `Sentry::Cron::MonitorCheckIns` module for automatic monitoring of jobs [#2130](https://github.com/getsentry/sentry-ruby/pull/2130)

    Standard job frameworks such as `ActiveJob` and `Sidekiq` can now use this module to automatically capture check ins.

    ```rb
    class ExampleJob < ApplicationJob
      include Sentry::Cron::MonitorCheckIns

      sentry_monitor_check_ins

      def perform(*args)
        # do stuff
      end
    end
    ```

    ```rb
    class SidekiqJob
      include Sidekiq::Job
      include Sentry::Cron::MonitorCheckIns

      sentry_monitor_check_ins

      def perform(*args)
        # do stuff
      end
    end
    ```

    You can pass in optional attributes to `sentry_monitor_check_ins` as follows.

    ```rb
    # slug defaults to the job class name
    sentry_monitor_check_ins slug: 'custom_slug'

    # define the monitor config with an interval
    sentry_monitor_check_ins monitor_config: Sentry::Cron::MonitorConfig.from_interval(1, :minute)

    # define the monitor config with a crontab
    sentry_monitor_check_ins monitor_config: Sentry::Cron::MonitorConfig.from_crontab('5 * * * *')
    ```

### Bug Fixes

- Rename `http.method` to `http.request.method` in `Span::DataConventions` [#2106](https://github.com/getsentry/sentry-ruby/pull/2106)
- Increase `Envelope::Item::MAX_SERIALIZED_PAYLOAD_SIZE` to 1MB [#2108](https://github.com/getsentry/sentry-ruby/pull/2108)
- Fix `db_config` begin `nil` in `ActiveRecordSubscriber` [#2111](https://github.com/getsentry/sentry-ruby/pull/2111)
  - Fixes [#2109](https://github.com/getsentry/sentry-ruby/issues/2109)
- Always send envelope trace header from dynamic sampling context [#2113](https://github.com/getsentry/sentry-ruby/pull/2113)
- Improve `TestHelper`'s setup/teardown helpers ([#2116](https://github.com/getsentry/sentry-ruby/pull/2116))
  - Fixes [#2103](https://github.com/getsentry/sentry-ruby/issues/2103)
- Fix Sidekiq tracing headers not being overwritten in case of schedules and retries [#2118](https://github.com/getsentry/sentry-ruby/pull/2118)
- Fix exception event sending failed due to source sequence is illegal/malformed utf-8 [#2083](https://github.com/getsentry/sentry-ruby/pull/2083)
  - Fixes [#2082](https://github.com/getsentry/sentry-ruby/issues/2082)

## 5.11.0

### Features

- Make `:value` in `SingleExceptionInterface` writable, so that it can be modified in `before_send` under `event.exception.values[n].value` [#2072](https://github.com/getsentry/sentry-ruby/pull/2072)
- Add `sampled` field to `dynamic_sampling_context` [#2092](https://github.com/getsentry/sentry-ruby/pull/2092)
- Consolidate HTTP span data conventions with OpenTelemetry with `Sentry::Span::DataConventions`  [#2093](https://github.com/getsentry/sentry-ruby/pull/2093)
- Consolidate database span data conventions with OpenTelemetry for ActiveRecord and Redis [#2100](https://github.com/getsentry/sentry-ruby/pull/2100)
- Add new `config.trace_propagation_targets` option to set targets for which headers are propagated in outgoing HTTP requests [#2079](https://github.com/getsentry/sentry-ruby/pull/2079)

  ```rb
  # takes an array of strings or regexps
  config.trace_propagation_targets = [/.*/]  # default is to all targets
  config.trace_propagation_targets = [/example.com/, 'foobar.org/api/v2']
  ```

- Tracing without Performance
  - Implement `PropagationContext` on `Scope` and add `Sentry.get_trace_propagation_headers` API [#2084](https://github.com/getsentry/sentry-ruby/pull/2084)
  - Implement `Sentry.continue_trace` API [#2089](https://github.com/getsentry/sentry-ruby/pull/2089)

  The SDK now supports connecting arbitrary events (Errors / Transactions / Replays) across distributed services and not just Transactions.
  To continue an incoming trace starting with this version of the SDK, use `Sentry.continue_trace` as follows.

  ```rb
  # rack application
  def call(env)
    transaction = Sentry.continue_trace(env, name: 'transaction', op: 'op')
    Sentry.start_transaction(transaction: transaction)
  end
  ```

  To inject headers into outgoing requests, use `Sentry.get_trace_propagation_headers` to get a hash of headers to add to your request.

### Bug Fixes

- Duplicate `Rails.logger` before assigning it to the SDK ([#2086](https://github.com/getsentry/sentry-ruby/pull/2086))

## 5.10.0

### Features

- Move `http.query` to span data in net/http integration [#2039](https://github.com/getsentry/sentry-ruby/pull/2039)
- Validate `release` is a `String` during configuration [#2040](https://github.com/getsentry/sentry-ruby/pull/2040)
- Allow JRuby Java exceptions to be captured [#2043](https://github.com/getsentry/sentry-ruby/pull/2043)
- Improved error handling around `traces_sample_rate`/`profiles_sample_rate` [#2036](https://github.com/getsentry/sentry-ruby/pull/2036)

### Bug Fixes

- Support Rails 7.1's show exception check [#2049](https://github.com/getsentry/sentry-ruby/pull/2049)
- Fix uninitialzed race condition in Redis integration [#2057](https://github.com/getsentry/sentry-ruby/pull/2057)
  - Fixes [#2054](https://github.com/getsentry/sentry-ruby/issues/2054)
- Ignore low-level Puma exceptions by default [#2055](https://github.com/getsentry/sentry-ruby/pull/2055)
- Use allowlist to filter `ActiveSupport` breadcrumbs' data [#2048](https://github.com/getsentry/sentry-ruby/pull/2048)
- ErrorHandler should cleanup the scope ([#2059](https://github.com/getsentry/sentry-ruby/pull/2059))

## 5.9.0

### Features

- Add new boolean option `config.enable_tracing` to simplify enabling performance tracing [#2005](https://github.com/getsentry/sentry-ruby/pull/2005)
  - `config.enable_tracing = true` will set `traces_sample_rate` to `1.0` if not set already
  - `config.enable_tracing = false` will turn off tracing even if `traces_sample_rate/traces_sampler` is set
  - `config.enable_tracing = nil` (default) will keep the current behaviour
- Allow ignoring `excluded_exceptions` when manually capturing exceptions [#2007](https://github.com/getsentry/sentry-ruby/pull/2007)

  Users can now ignore the SDK's `excluded_exceptions` by passing `ignore_exclusions` hint when using `Sentry.capture_exception`.

  ```rb
  # assume ignored_exception.class is included in config.excluded_exception
  Sentry.capture_exception(ignored_exception) # won't be sent to Sentry
  Sentry.capture_exception(ignored_exception, hint: { ignore_exclusions: true }) # will be sent to Sentry
  ```

- Support capturing low-level errors propagated to Puma [#2026](https://github.com/getsentry/sentry-ruby/pull/2026)

- Add `spec` to `Backtrace::APP_DIRS_PATTERN` [#2029](https://github.com/getsentry/sentry-ruby/pull/2029)
- Forward all `baggage` header items that are prefixed with `sentry-` [#2025](https://github.com/getsentry/sentry-ruby/pull/2025)
- Add `stackprof` based profiler [#2024](https://github.com/getsentry/sentry-ruby/pull/2024)

  The SDK now supports sending profiles taken by the [`stackprof` gem](https://github.com/tmm1/stackprof) and viewing them in the [Profiling](https://docs.sentry.io/product/profiling/) section.

  To use it, first add `stackprof` to your `Gemfile` and make sure it is loaded before `sentry-ruby`.

  ```ruby
  # Gemfile

  gem 'stackprof'
  gem 'sentry-ruby'
  ```

  Then, make sure both `traces_sample_rate` and `profiles_sample_rate` are set and non-zero in your sentry initializer.

  ```ruby
  # config/initializers/sentry.rb

  Sentry.init do |config|
    config.dsn = "<dsn>"
    config.traces_sample_rate = 1.0
    config.profiles_sample_rate = 1.0
  end
  ```

  Some implementation caveats:
  - Profiles are sampled **relative** to traces, so if both rates are 0.5, we will capture 0.25 of all requests.
  - Profiles are only captured for code running within a transaction.
  - Profiles for multi-threaded servers like `puma` might not capture frames correctly when async I/O is happening. This is a `stackprof` limitation.

  <br />

  > **Warning**
  > Profiling is currently in beta. Beta features are still in-progress and may have bugs. We recognize the irony.
  > If you have any questions or feedback, please email us at <profiling@sentry.io>, reach out via Discord (#profiling), or open an issue.

### Bug Fixes

- Validate that contexts set in `set_contexts` are also Hash instances [#2022](https://github.com/getsentry/sentry-ruby/pull/2022/files)
  - Fixes [#2021](https://github.com/getsentry/sentry-ruby/issues/2021)

## 5.8.0

### Features

- Allow [tags](https://docs.sentry.io/platforms/ruby/enriching-events/tags/) to be passed via the context hash when reporting errors using ActiveSupport::ErrorReporter and Sentry::Rails::ErrorSubscriber in `sentry-rails` [#1932](https://github.com/getsentry/sentry-ruby/pull/1932)
- Pass a `cached: true` tag for SQL query spans that utilized the ActiveRecord QueryCache when using ActiveRecordSubscriber in `sentry-rails` [#1968](https://github.com/getsentry/sentry-ruby/pull/1968)
- Add `Sentry.add_global_event_processor` API [#1976](https://github.com/getsentry/sentry-ruby/pull/1976)

    Users can now configure global event processors without configuring scope as well.

    ```rb
    Sentry.add_global_event_processor do |event, hint|
      event.tags = { foo: 42 }
      event
    end
    ```

- Add global event processor in OpenTelemetry `SpanProcessor` to link errors with transactions [#1983](https://github.com/getsentry/sentry-ruby/pull/1983)
- Fix some inconsistencies in setting name/op/status in OpenTelemetry `SpanProcessor` [#1987](https://github.com/getsentry/sentry-ruby/pull/1987)
- Add `config.before_send_transaction` hook [#1989](https://github.com/getsentry/sentry-ruby/pull/1989)

    Users can now configure a `before_send_transaction` callback that runs similar to `before_send` but for transaction events.

    ```rb
    config.before_send_transaction = lambda do |event, hint|
      # skip unimportant transactions or strip sensitive data
      if event.transaction == "/healthcheck/route"
        nil
      else
        event
      end
    end
    ```

- Support `Sentry::Transaction#set_measurement` [#1838](https://github.com/getsentry/sentry-ruby/pull/1838)

    Usage:

    ```rb
    transaction = Sentry.get_current_scope.get_transaction
    transaction.set_measurement("metrics.foo", 0.5, "millisecond")
    ```

### Bug Fixes

- Support redis-rb 5.0+ [#1963](https://github.com/getsentry/sentry-ruby/pull/1963)
  - Fixes [#1932](https://github.com/getsentry/sentry-ruby/pull/1932)
- Skip private _config context in Sidekiq 7+ [#1967](https://github.com/getsentry/sentry-ruby/pull/1967)
  - Fixes [#1956](https://github.com/getsentry/sentry-ruby/issues/1956)
- Return value from `perform_action` in ActionCable::Channel instances when initialized [#1966](https://github.com/getsentry/sentry-ruby/pull/1966)
- `Span#with_child_span` should finish the span even with exception raised [#1982](https://github.com/getsentry/sentry-ruby/pull/1982)
- Fix sentry-rails' controller span nesting [#1973](https://github.com/getsentry/sentry-ruby/pull/1973)
  - Fixes [#1899](https://github.com/getsentry/sentry-ruby/issues/1899)
- Do not report exceptions when a Rails runner exits with `exit 0` [#1988](https://github.com/getsentry/sentry-ruby/pull/1988)
- Ignore redis key if not UTF8 [#1997](https://github.com/getsentry/sentry-ruby/pull/1997)
  - Fixes [#1992](https://github.com/getsentry/sentry-ruby/issues/1992)

### Miscellaneous

- Deprecate `capture_exception_frame_locals` in favor of `include_local_variables` [#1993](https://github.com/getsentry/sentry-ruby/pull/1993)

## 5.7.0

### Features

- Expose `span_id` in `Span` constructor [#1945](https://github.com/getsentry/sentry-ruby/pull/1945)
- Expose `end_timestamp` in `Span#finish` and `Transaction#finish` [#1946](https://github.com/getsentry/sentry-ruby/pull/1946)
- Add `Transaction#set_context` api [#1947](https://github.com/getsentry/sentry-ruby/pull/1947)
- Add OpenTelemetry support with new `sentry-opentelemetry` gem
  - Add `config.instrumenter` to switch between `:sentry` and `:otel` instrumentation [#1944](https://github.com/getsentry/sentry-ruby/pull/1944)

    The new `sentry-opentelemetry` gem adds support to automatically integrate OpenTelemetry performance tracing with Sentry. [Give it a try](https://github.com/getsentry/sentry-ruby/tree/master/sentry-opentelemetry#getting-started) and let us know if you have any feedback or problems with using it.

## 5.6.0

### Features

- Allow users to configure their asset-skipping pattern [#1915](https://github.com/getsentry/sentry-ruby/pull/1915)

    Users can now configure their own pattern to skip asset requests' transactions

    ```rb
    Sentry.init do |config|
      config.rails.assets_regexp = /my_regexp/
    end
    ```

- Use `Sentry.with_child_span` in redis and net/http instead of `span.start_child` [#1920](https://github.com/getsentry/sentry-ruby/pull/1920)
  - This might change the nesting of some spans and make it more accurate
  - Followup fix to set the sentry-trace header in the correct place [#1922](https://github.com/getsentry/sentry-ruby/pull/1922)

- Use `Exception#detailed_message` when generating exception message if applicable [#1924](https://github.com/getsentry/sentry-ruby/pull/1924)
- Make `sentry-sidekiq` compatible with Sidekiq 7 [#1930](https://github.com/getsentry/sentry-ruby/pull/1930)

### Bug Fixes

- `Sentry::BackgroundWorker` will release `ActiveRecord` connection pool only when the `ActiveRecord` connection is established
- Remove bad encoding arguments in redis span descriptions [#1914](https://github.com/getsentry/sentry-ruby/pull/1914)
  - Fixes [#1911](https://github.com/getsentry/sentry-ruby/issues/1911)
- Add missing `initialized?` checks to `sentry-rails` [#1919](https://github.com/getsentry/sentry-ruby/pull/1919)
  - Fixes [#1885](https://github.com/getsentry/sentry-ruby/issues/1885)
- Update Tracing Span's op names [#1923](https://github.com/getsentry/sentry-ruby/pull/1923)

    Currently, Ruby integrations' Span op names aren't aligned with the core specification's convention, so we decided to update them altogether in this PR.
    **If you rely on Span op names for fine-grained event filtering, this may affect the data your app sends to Sentry.**
    **Also make sure to update your [`traces_sampler`](https://docs.sentry.io/platforms/ruby/configuration/sampling/#setting-a-sampling-function) if you rely on the `op` for filtering some requests.**

### Refactoring

- Make transaction a required argument of Span [#1921](https://github.com/getsentry/sentry-ruby/pull/1921)

## 5.5.0

### Features

- Support rack 3 [#1884](https://github.com/getsentry/sentry-ruby/pull/1884)
  - We no longer need the `HTTP_VERSION` check for ignoring the header

- Add [Dynamic Sampling](https://docs.sentry.io/product/sentry-basics/sampling/) support
  The SDK now supports Sentry's Dynamic Sampling product.

  Note that this is not supported for users still using the `config.async` option.

  - Parse incoming [W3C Baggage Headers](https://www.w3.org/TR/baggage/) and propagate them to continue traces [#1869](https://github.com/getsentry/sentry-ruby/pull/1869)
    - in all outgoing requests in our net/http patch
    - in Sentry transactions as [Dynamic Sampling Context](https://develop.sentry.dev/sdk/performance/dynamic-sampling-context/)
  - Create new Baggage entries as Head SDK (originator of trace) [#1898](https://github.com/getsentry/sentry-ruby/pull/1898)
  - Add Transaction source annotations to classify low quality (high cardinality) transaction names [#1902](https://github.com/getsentry/sentry-ruby/pull/1902)

### Bug Fixes

- Memoize session.aggregation_key [#1892](https://github.com/getsentry/sentry-ruby/pull/1892)
  - Fixes [#1891](https://github.com/getsentry/sentry-ruby/issues/1891)
- Execute `with_scope`'s block even when SDK is not initialized [#1897](https://github.com/getsentry/sentry-ruby/pull/1897)
  - Fixes [#1896](https://github.com/getsentry/sentry-ruby/issues/1896)
- Make sure test helper clears the current scope before/after a test [#1900](https://github.com/getsentry/sentry-ruby/pull/1900)

## 5.4.2

### Bug Fixes

- Fix sentry_logger when SDK is closed from another thread [#1860](https://github.com/getsentry/sentry-ruby/pull/1860)
  - Fixes [#1858](https://github.com/getsentry/sentry-ruby/issues/1858)

## 5.4.1

### Bug Fixes

- Fix missing `spec.files` in `sentry-ruby.gemspec`
  - Fixes [#1856](https://github.com/getsentry/sentry-ruby/issues/1856)

## 5.4.0

### Features

- Expose `:values` in `ExceptionInterface`, so that it can be accessed in `before_send` under `event.exception.values` [#1843](https://github.com/getsentry/sentry-ruby/pull/1843)

- Add top level `Sentry.close` API [#1844](https://github.com/getsentry/sentry-ruby/pull/1844)
  - Cleans up SDK state and sets it to uninitialized
  - No-ops all SDK APIs and also disables the transport layer, so nothing will be sent to Sentry after closing the SDK

- Handle exception with large stacktrace without dropping entire item [#1807](https://github.com/getsentry/sentry-ruby/pull/1807)
- Capture Rails runner's exceptions before exiting [#1820](https://github.com/getsentry/sentry-ruby/pull/1820)

- Add `Sentry.with_exception_captured` helper [#1814](https://github.com/getsentry/sentry-ruby/pull/1814)

    Usage:

    ```rb
    Sentry.with_exception_captured do
     1/1 #=> 1 will be returned
    end

    Sentry.with_exception_captured do
     1/0 #=> ZeroDivisionError will be reported and re-raised
    end
    ```

- Prepare for Rails 7.1's error reporter API change [#1834](https://github.com/getsentry/sentry-ruby/pull/1834)
- Set `sentry.error_event_id` in request env if the middleware captures errors [#1849](https://github.com/getsentry/sentry-ruby/pull/1849)

  If the SDK's Rack middleware captures an error, the reported event's id will be stored in the request env. For example:

  ```rb
  env["sentry.error_event_id"] #=> "507bd4c1a07e4355bb70bcd7afe8ab17"
  ```

  Users can display this information on the error page via a middleware as proposed in [#1846](https://github.com/getsentry/sentry-ruby/issues/1846)

### Bug Fixes

- Respect `report_rescued_exceptions` config [#1847](https://github.com/getsentry/sentry-ruby/pull/1847)
  - Fixes [#1840](https://github.com/getsentry/sentry-ruby/issues/1840)
- Rescue event's to JSON conversion error [#1853](https://github.com/getsentry/sentry-ruby/pull/1853)
- Rescue `ThreadError` in `SessionFlusher` and stop creating threads if flusher is killed [#1851](https://github.com/getsentry/sentry-ruby/issues/1851)
  - Fixes [#1848](https://github.com/getsentry/sentry-ruby/issues/1848)

### Refactoring

- Move envelope item processing/trimming logic to the Item class [#1824](https://github.com/getsentry/sentry-ruby/pull/1824)
- Replace sentry-ruby-core with sentry-ruby as integration dependency [#1825](https://github.com/getsentry/sentry-ruby/pull/1825)

### Test Helpers

The SDK now provides a set of [test helpers](https://github.com/getsentry/sentry-ruby/blob/master/sentry-ruby/lib/sentry/test_helper.rb) to help users setup and teardown Sentry related tests.

To get started:

```rb
require "sentry/test_helper"

# in minitest
class MyTest < Minitest::Test
  include Sentry::TestHelper
  # ...
end

# in RSpec
RSpec.configure do |config|
  config.include Sentry::TestHelper
  # ...
end
```

It's still an early attempt so please give us feedback in [#1680](https://github.com/getsentry/sentry-ruby/issues/1680).

## 5.3.1

### Bug Fixes

- Don't require a DB connection, but release one if it is acquired [#1812](https://github.com/getsentry/sentry-ruby/pull/1812)
  - Fixes [#1808](https://github.com/getsentry/sentry-ruby/issues/1808)
- `Sentry.with_child_span` should check SDK's initialization state [#1819](https://github.com/getsentry/sentry-ruby/pull/1819)
  - Fixes [#1818](https://github.com/getsentry/sentry-ruby/issues/1818)

### Miscellaneous

- Warn users about `config.async`'s deprecation [#1803](https://github.com/getsentry/sentry-ruby/pull/1803)

## 5.3.0

### Features

- Add `Sentry.with_child_span` for easier span recording [#1783](https://github.com/getsentry/sentry-ruby/pull/1783)

```rb
operation_result = Sentry.with_child_span(op: "my op") do |child_span|
  my_operation
end

# the "my op" span will be attached to the result of Sentry.get_current_scope.get_span
# which could be either the top-level transaction, or a span set by the user or other integrations
```

### Bug Fixes

- Set `last_event_id` only for error events [#1767](https://github.com/getsentry/sentry-ruby/pull/1767)
  - Fixes [#1766](https://github.com/getsentry/sentry-ruby/issues/1766)
- Add `config.rails.register_error_subscriber` to control error reporter integration [#1771](https://github.com/getsentry/sentry-ruby/pull/1771)
  - Fixes [#1731](https://github.com/getsentry/sentry-ruby/issues/1731), [#1754](https://github.com/getsentry/sentry-ruby/issues/1754), and [#1765](https://github.com/getsentry/sentry-ruby/issues/1765)
  - [Discussion thread and explanation on the decision](https://github.com/rails/rails/pull/43625#issuecomment-1072514175)
- Check if ActiveRecord connection exists before calling AR connection pool [#1769](https://github.com/getsentry/sentry-ruby/pull/1769)
  - Fixes [#1745](https://github.com/getsentry/sentry-ruby/issues/1745)
- Fix `sentry-rails`'s tracing spans not nesting issue - [#1784](https://github.com/getsentry/sentry-ruby/pull/1784)
  - Fixes [#1723](https://github.com/getsentry/sentry-ruby/issues/1723)
- Update `config.transport.proxy` to allow String and URI values as previously supported by `sentry-ruby` versions <= 4.8 using Faraday
  - Fixes [#1782](https://github.com/getsentry/sentry-ruby/issues/1782)
- Register SentryContextClientMiddleware on sidekiq workers [#1774](https://github.com/getsentry/sentry-ruby/pull/1774)
- Add request env to sampling context when using `sentry-rails` [#1792](https://github.com/getsentry/sentry-ruby/pull/1792)
  - Fixes [#1791](https://github.com/getsentry/sentry-ruby/issues/1791)
- Fix net-http tracing's span nesting issue [#1796](https://github.com/getsentry/sentry-ruby/pull/1796)

### Refactoring

- Correct inaccurate event model relationships [#1777](https://github.com/getsentry/sentry-ruby/pull/1777)

### Miscellaneous

- Log message when shutting down/killing SDK managed components [#1779](https://github.com/getsentry/sentry-ruby/pull/1779)

## 5.2.1

### Bug Fixes

- Also check stringified breadcrumbs key when reducing payload size [#1758](https://github.com/getsentry/sentry-ruby/pull/1758)
  - Fixes [#1757](https://github.com/getsentry/sentry-ruby/issues/1757)
- Ignore internal Sidekiq::JobRetry::Skip exception [#1763](https://github.com/getsentry/sentry-ruby/pull/1763)
  - Fixes [#1731](https://github.com/getsentry/sentry-ruby/issues/1731)

### Miscellaneous

- Warn user if any integration is required after SDK initialization [#1759](https://github.com/getsentry/sentry-ruby/pull/1759)

## 5.2.0

### Features

- Log Redis command arguments when sending PII is enabled [#1726](https://github.com/getsentry/sentry-ruby/pull/1726)
- Add request env to sampling context [#1749](https://github.com/getsentry/sentry-ruby/pull/1749)

  **Example**

  ```rb
  Sentry.init do |config|
    config.traces_sampler = lambda do |sampling_context|
      env = sampling_context[:env]

      if env["REQUEST_METHOD"] == "GET"
        0.01
      else
        0.1
      end
    end
  end
  ```

- Check envelope size before sending it [#1747](https://github.com/getsentry/sentry-ruby/pull/1747)

  The SDK will now check if the envelope's event items are oversized before sending the envelope. It goes like this:

  1. If an event is oversized (200kb), the SDK will remove its breadcrumbs (which in our experience is the most common cause).
  2. If the event size now falls within the limit, it'll be sent.
  3. Otherwise, the event will be thrown away. The SDK will also log a debug message about the event's attributes size (in bytes) breakdown. For example,

  ```
  {event_id: 34, level: 7, timestamp: 22, environment: 13, server_name: 14, modules: 935, message: 5, user: 2, tags: 2, contexts: 820791, extra: 2, fingerprint: 2, platform: 6, sdk: 40, threads: 51690}
  ```

  This will help users report size-related issues in the future.

- Automatic session tracking [#1715](https://github.com/getsentry/sentry-ruby/pull/1715)

  **Example**:

  <img width="80%" src="https://user-images.githubusercontent.com/6536764/157057827-2893527e-7973-4901-a070-bd78a720574a.png">

  The SDK now supports [automatic session tracking / release health](https://docs.sentry.io/product/releases/health/) by default in Rack based applications.
  Aggregate statistics on successful / errored requests are collected and sent to the server every minute.
  To use this feature, make sure the SDK can detect your app's release. Or you have set it with:

  ```ruby
  Sentry.init do |config|
    config.release = 'release-foo-v1'
  end
  ```

  To disable this feature, set `config.auto_session_tracking` to `false`.

### Bug Fixes

- Require set library [#1753](https://github.com/getsentry/sentry-ruby/pull/1753)
  - Fixes [#1752](https://github.com/getsentry/sentry-ruby/issues/1752)

## 5.1.1

### Bug Fixes

- Allow overwriting of context values [#1724](https://github.com/getsentry/sentry-ruby/pull/1724)
  - Fixes [#1722](https://github.com/getsentry/sentry-ruby/issues/1722)
- Avoid duplicated capturing on the same exception object [#1738](https://github.com/getsentry/sentry-ruby/pull/1738)
  - Fixes [#1731](https://github.com/getsentry/sentry-ruby/issues/1731)

### Refactoring

- Encapsulate extension helpers [#1725](https://github.com/getsentry/sentry-ruby/pull/1725)
- Move rate limiting logic to each item in envelope [#1742](https://github.com/getsentry/sentry-ruby/pull/1742)

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
