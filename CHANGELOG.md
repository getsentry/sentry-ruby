## Unreleased

- Queue time capture for Rack ([#2838](https://github.com/getsentry/sentry-ruby/pull/2838))

## 6.3.0

### Features

- Implement new `Sentry.metrics` functionality ([#2818](https://github.com/getsentry/sentry-ruby/pull/2818))

  The SDK now supports Sentry's new [Trace Connected Metrics](https://docs.sentry.io/product/explore/metrics/) product.

  ```ruby
   Sentry.metrics.count("button.click", 1, attributes: { button_id: "submit" })
   Sentry.metrics.distribution("response.time", 120.5, unit: "millisecond")
   Sentry.metrics.gauge("cpu.usage", 75.2, unit: "percent")
  ```

  Metrics is enabled by default and only activates once you use the above APIs. To disable completely:

  ```ruby
  Sentry.init do |config|
    # ...
    config.enable_metrics = false
  end
  ```

- Support for tracing `Sequel` queries ([#2814](https://github.com/getsentry/sentry-ruby/pull/2814))

  ```ruby
  require "sentry"
  require "sentry/sequel"

  Sentry.init do |config|
    config.enabled_patches << :sequel
  end

  DB = Sequel.sqlite
  DB.extension(:sentry)
  ```

- Add support for OpenTelemetry messaging/queue system spans ([#2685](https://github.com/getsentry/sentry-ruby/pull/2685))

- Add support for `config.std_lib_logger_filter` proc ([#2829](https://github.com/getsentry/sentry-ruby/pull/2829))

  ```ruby
  Sentry.init do |config|
    config.std_lib_logger_filter = proc do |logger, message, severity|
      # Only send ERROR and above messages
      severity == :error || severity == :fatal
    end

    config.enabled_patches = [:std_lib_logger]
  end
  ```

### Bug Fixes

- Handle empty frames case gracefully with local vars ([#2807](https://github.com/getsentry/sentry-ruby/pull/2807))
- Handle more extra attribute types when using `extra` attributes for structured logging ([#2815](https://github.com/getsentry/sentry-ruby/pull/2815))
  ```ruby
  # This now works too and the nested hash is dumped to JSON string
  Sentry.logger.info("Hello World", extra: { today: Date.today, user_id: user.id })
  ```
- Prevent SDK crash when SDK logging fails ([#2817](https://github.com/getsentry/sentry-ruby/pull/2817))

### Internal

- Unify Logs and Metrics implementations ([#2826](https://github.com/getsentry/sentry-ruby/pull/2826))
- Unify LogEventBuffer and MetricEventBuffer logic ([#2830](https://github.com/getsentry/sentry-ruby/pull/2830))
- Add maximum limits on LogEventBuffer (1k) and MetricEventBuffer (10k) for protection from memory blowup ([#2831](https://github.com/getsentry/sentry-ruby/pull/2831))
- Lazily start LogEventBuffer and MetricEventBuffer threads ([#2832](https://github.com/getsentry/sentry-ruby/pull/2832))

## 6.2.0

### Features

- Include otel as custom sampling context ([2683](https://github.com/getsentry/sentry-ruby/pull/2683))
- Ignore new rails rate limit errors ([#2774](https://github.com/getsentry/sentry-ruby/pull/2774))

### Fixes

- Prevent logging from crashing main thread ([2795](https://github.com/getsentry/sentry-ruby/pull/2795))
- Improve error handling in ActiveRecord subscriber ([2798](https://github.com/getsentry/sentry-ruby/pull/2798))

## 6.1.2

### Fixes

- Handle positioned binds in logging ([#2787](https://github.com/getsentry/sentry-ruby/pull/2787))
- Handle cached queries with binds correctly when logging ([#2789](https://github.com/getsentry/sentry-ruby/pull/2789))

## 6.1.1

### Improvements

- Optimize getting query source location in ActiveRecord tracing - this makes tracing up to roughly 40-60% faster depending on the use cases ([#2769](https://github.com/getsentry/sentry-ruby/pull/2769))

### Bug fixes

- Properly skip silenced `ActiveRecord::Base.logger`'s log entries in the ActiveRecord log subscriber ([#2775](https://github.com/getsentry/sentry-ruby/pull/2775))
- Handle malformed utf-8 log messages and attributes ([#2777](https://github.com/getsentry/sentry-ruby/pull/2777) and [#2780](https://github.com/getsentry/sentry-ruby/pull/2780))
- Fix initialized check in Sentry::Rails::CaptureExceptions ([#2783](https://github.com/getsentry/sentry-ruby/pull/2783))

## 6.1.0

### Features

- Add support for ActiveRecord binds in the log events ([#2761](https://github.com/getsentry/sentry-ruby/pull/2761))

### Bug Fixes

- Guard log subscribers with initialized check ([#2765](https://github.com/getsentry/sentry-ruby/pull/2765))

## 6.0.0

### Breaking Changes

- Drop support for rubies below 2.7 [#2743](https://github.com/getsentry/sentry-ruby/pull/2743)
  - Drop support for Rails below 5.2.0
  - Drop support for Sidekiq below 5.0
- Remove deprecated `config.async` [#1894](https://github.com/getsentry/sentry-ruby/pull/1894)
- Remove deprecated `Sentry::Metrics` and `config.metrics` and all metrics related code ([#2729](https://github.com/getsentry/sentry-ruby/pull/2729))
- Remove deprecated `config.capture_exception_frame_locals`, use `include_local_variables` instead ([#2730](https://github.com/getsentry/sentry-ruby/pull/2730))
- Remove deprecated `config.enable_tracing`, use `config.traces_sample_rate = 1.0` instead ([#2731](https://github.com/getsentry/sentry-ruby/pull/2731))
- Remove deprecated `config.logger=`, use `config.sdk_logger=` instead ([#2732](https://github.com/getsentry/sentry-ruby/pull/2732))
- `Sentry.logger` now always points to the `StructuredLogger` ([#2752](https://github.com/getsentry/sentry-ruby/pull/2752))
- Remove deprecated `Sentry::Rails::Tracing::ActionControllerSubscriber` ([#2733](https://github.com/getsentry/sentry-ruby/pull/2733))
- Remove deprecated `Event#configuration` ([#2740](https://github.com/getsentry/sentry-ruby/pull/2740))
- Remove deprecated `Sentry::Client#generate_sentry_trace` and `Sentry::Client#generate_baggage` ([#2741](https://github.com/getsentry/sentry-ruby/pull/2741))
- Remove `Transaction` deprecations ([#2736](https://github.com/getsentry/sentry-ruby/pull/2736))
  - Remove deprecated constant `Sentry::Transaction::SENTRY_TRACE_REGEXP`, use `Sentry::PropagationContext::SENTRY_TRACE_REGEXP` instead
  - Remove deprecated method `Sentry::Transaction.from_sentry_trace`, use `Sentry.continue_trace` instead
  - Remove deprecated method `Sentry::Transaction.extract_sentry_trace`, use `Sentry::PropagationContext.extract_sentry_trace` instead
  - Remove deprecated attribute `Sentry::Transaction.configuration`
  - Remove deprecated attribute `Sentry::Transaction.hub`
  - Remove deprecated argument `hub` to `Sentry::Transaction.finish`
  - Remove deprecated argument `hub` to `Sentry::Transaction#initialize` ([#2739](https://github.com/getsentry/sentry-ruby/pull/2739))
- Remove `:monotonic_active_support_logger` from `config.breadcrumbs_logger` ([#2717](https://github.com/getsentry/sentry-ruby/pull/2717))
- Migrate from to_hash to to_h ([#2351](https://github.com/getsentry/sentry-ruby/pull/2351))
- Add `before_send_check_in` for applying to `CheckInEvent` ([#2703](https://github.com/getsentry/sentry-ruby/pull/2703))
- Returning a hash from `before_send` and `before_send_transaction` is no longer supported and will drop the event.
- `config.enabled_environments` now defaults to `nil` instead of `[]` for sending to all environments ([#2716](https://github.com/getsentry/sentry-ruby/pull/2716))
- Requests which have response status codes in the inclusive ranges `[(301..303), (305..399), (401..404)]` will no longer create transactions by default. See `config.trace_ignore_status_codes` below to control what gets traced.
- Stacktrace truncation for oversized events now takes 500 frames on each side instead of 250.

### Features

- Add `config.trace_ignore_status_codes` to control which response codes to ignore for tracing ([#2725](https://github.com/getsentry/sentry-ruby/pull/2725))

  You can pass in an Array of individual status codes or ranges of status codes.

  ```ruby
  Sentry.init do |config|
      # ...
      # will ignore 404, 501, 502, 503
      config.trace_ignore_status_codes = [404, (501..503)]
  end
  ```

- Add `config.profiles_sample_interval` to control sampling frequency ([#2745](https://github.com/getsentry/sentry-ruby/pull/2745))
  - Both `stackprof` and `vernier` now get sampled at a default frequency of 101 Hz.
- Request body reading checks for `:rewind` to match Rack 3 behavior. ([#2754](https://github.com/getsentry/sentry-ruby/pull/2754))

### Internal

- Archive [`sentry-raven`](https://github.com/getsentry/raven-ruby) ([#2708](https://github.com/getsentry/sentry-ruby/pull/2708))
- Don't send `sample_rate` client reports for profiles if profiling is disabled ([#2728](https://github.com/getsentry/sentry-ruby/pull/2728))

## 5.28.1

### Bug Fixes

- The `sentry.origin` log event attribute is now correctly prefixed with `auto.log` ([#2749](https://github.com/getsentry/sentry-ruby/pull/2749))

## 5.28.0

### Features

- Auto-enable Rails structured logging when `enable_logs` is true ([#2721](https://github.com/getsentry/sentry-ruby/pull/2721))

### Miscellaneous

- Deprecate all Metrics related APIs [#2726](https://github.com/getsentry/sentry-ruby/pull/2726)

  Sentry [no longer has the Metrics Beta offering](https://sentry.zendesk.com/hc/en-us/articles/26369339769883-Metrics-Beta-Ended-on-October-7th) so
  all the following APIs linked to Metrics have been deprecated and will be removed in the next major.

  ```ruby
  Sentry.init do |config|
    # ...
    config.metrics.enabled = true
    config.metrics.enable_code_locations = true
    config.metrics.before_emit = lambda {}
  end

  Sentry::Metrics.increment('button_click')
  Sentry::Metrics.distribution('page_load', 15.0, unit: 'millisecond')
  Sentry::Metrics.gauge('page_load', 15.0, unit: 'millisecond')
  Sentry::Metrics.set('user_view', 'jane')
  Sentry::Metrics.timing('how_long') { sleep(1) }
  ```

### Internal

- Fix leftover `config.logger` call in `graphql` patch ([#2722](https://github.com/getsentry/sentry-ruby/2722)
- Add `Configuration.before` and `Configuration.after` to run hooks before and after given event ([#2724](https://github.com/getsentry/sentry-ruby/pull/2724))

## 5.27.1

### Features

- Support for `:origin` attribute in log events ([#2712](https://github.com/getsentry/sentry-ruby/pull/2712))

### Bug Fixes

- Skip including `sentry.message.template` in the log event attributes if there are no interpolation parameters provided ([#2700](https://github.com/getsentry/sentry-ruby/pull/2700))
- Respect `log_level` when logging via `:std_lib_logger` patch ([#2709](https://github.com/getsentry/sentry-ruby/pull/2709))
- Add `sentry.origin` attribute to log events ([#2712](https://github.com/getsentry/sentry-ruby/pull/2712))

## 5.27.0

### Features

- Propagated sampling rates as specified in [Traces](https://develop.sentry.dev/sdk/telemetry/traces/#propagated-random-value) docs ([#2671](https://github.com/getsentry/sentry-ruby/pull/2671))
- Support for Rails ActiveSupport log subscribers ([#2690](https://github.com/getsentry/sentry-ruby/pull/2690))
- Support for defining custom Rails log subscribers that work with Sentry Structured Logging ([#2689](https://github.com/getsentry/sentry-ruby/pull/2689))

  Rails applications can now define custom log subscribers that integrate with Sentry's structured logging system. The feature includes built-in subscribers for ActionController, ActiveRecord, ActiveJob, and ActionMailer events, with automatic parameter filtering that respects Rails' `config.filter_parameters` configuration.

  To enable structured logging with Rails log subscribers:

  ```ruby
  Sentry.init do |config|
    # ... your setup ...

    # Make sure structured logging is enabled
    config.enable_logs = true

    # Enable default Rails log subscribers (ActionController and ActiveRecord)
    config.rails.structured_logging.enabled = true
  end
  ```

  To configure all subscribers:

  ```ruby
  Sentry.init do |config|
    # ... your setup ...

    # Make sure structured logging is enabled
    config.enable_logs = true

    # Enable Rails log subscribers
    config.rails.structured_logging.enabled = true

    # Add ActionMailer and ActiveJob subscribers
    config.rails.structured_logging.subscribers.update(
      action_mailer: Sentry::Rails::LogSubscribers::ActionMailerSubscriber,
      active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber
    )
  end
  ```

  You can also define custom log subscribers by extending the base class:

  ```ruby
  class MyCustomSubscriber < Sentry::Rails::LogSubscriber
    attach_to :my_component

    def my_event(event)
      log_structured_event(
        message: "Custom event occurred",
        level: :info,
        attributes: { duration_ms: event.duration }
      )
    end
  end

  Sentry.init do |config|
    # ... your setup ...

    # Make sure structured logging is enabled
    config.enable_logs = true

    # Enable Rails log subscribers
    config.rails.structured_logging.enabled = true

    # Add custom subscriber
    config.rails.structured_logging.subscribers[:my_component] = MyCustomSubscriber
  end
  ```

- Introduce `structured_logging` config namespace ([#2692](https://github.com/getsentry/sentry-ruby/pull/2692))

### Bug Fixes

- Silence `_perform` method redefinition warning ([#2682](https://github.com/getsentry/sentry-ruby/pull/2682))
- Update sentry trace regexp ([#2678](https://github.com/getsentry/sentry-ruby/pull/2678))
- Remove redundant `attr_reader` ([#2673](https://github.com/getsentry/sentry-ruby/pull/2673))

### Internal

- Factor out do_request in HTTP transport ([#2662](https://github.com/getsentry/sentry-ruby/pull/2662))
- Add `Sentry::DebugTransport` that captures events and stores them as JSON for debugging purposes ([#2664](https://github.com/getsentry/sentry-ruby/pull/2664))
- Add `Sentry::DebugStructuredLogger` that caputres log events and stores them as JSON to a file for debugging purposes ([#2693](https://github.com/getsentry/sentry-ruby/pull/2693))
- Rails test runner ([#2687](https://github.com/getsentry/sentry-ruby/pull/2687))
- Update common gem deps for development ([#2688](https://github.com/getsentry/sentry-ruby/pull/2688))
- Make devcontainer work with ancient Ruby/Rails ([#2679](https://github.com/getsentry/sentry-ruby/pull/2679))
- Improved devcontainer setup with e2e test mini infra ([#2672](https://github.com/getsentry/sentry-ruby/pull/2672))
- Address various flaky specs
  - Fix test failures under JRuby ([#2665](https://github.com/getsentry/sentry-ruby/pull/2665))
  - Fix flaky faraday spec ([#2666](https://github.com/getsentry/sentry-ruby/pull/2666))
  - Fix flaky net/http spec ([#2667](https://github.com/getsentry/sentry-ruby/pull/2667))
  - Fix flaky tracing specs ([#2670](https://github.com/getsentry/sentry-ruby/pull/2670))

## 5.26.0

### Feature

- Support for `:logger` patch which enables sending logs to Sentry when `enabled_logs` is set to true ([#2657](https://github.com/getsentry/sentry-ruby/pull/2657))

  Here's a sample config:

  ```ruby
  Sentry.init do |config|
    # ... your setup ...
    config.enable_logs = true
    config.enabled_patches = [:logger]
  end
  ```

### Bug Fixes

- Skip creating `LogEventBuffer` if logging is not enabled ([#2652](https://github.com/getsentry/sentry-ruby/pull/2652))

## 5.25.0

### Features

- Support for `before_send_log` ([#2634](https://github.com/getsentry/sentry-ruby/pull/2634))
- Default user attributes are now automatically added to logs ([#2647](https://github.com/getsentry/sentry-ruby/pull/2647))

### Bug Fixes

- Structured logging consumes way less memory now ([#2643](https://github.com/getsentry/sentry-ruby/pull/2643))

## 5.24.0

### Features

- Add new sidekiq config `report_only_dead_jobs` ([#2581](https://github.com/getsentry/sentry-ruby/pull/2581))
- Add `max_nesting` of 10 to breadcrumbs data serialization ([#2583](https://github.com/getsentry/sentry-ruby/pull/2583))
- Add sidekiq config `propagate_traces` to control trace header injection ([#2588](https://github.com/getsentry/sentry-ruby/pull/2588))

  If you use schedulers you can get one large trace with all your jobs which is undesirable.
  We recommend using the following to propagate traces only from the Rails server and not elsewhere.

  ```ruby
  config.sidekiq.propagate_traces = false unless Rails.const_defined?('Server')
  ```

- Only expose `active_storage` keys on span data if `send_default_pii` is on ([#2589](https://github.com/getsentry/sentry-ruby/pull/2589))
- Add new `Sentry.logger` for [Structured Logging](https://develop.sentry.dev/sdk/telemetry/logs/) feature ([#2620](https://github.com/getsentry/sentry-ruby/pull/2620)).

  To enable structured logging you need to turn on the `enable_logs` configuration option:

  ```ruby
  Sentry.init do |config|
    # ... your setup ...
    config.enable_logs = true
  end
  ```

  Once you configured structured logging, you get access to a new `Sentry.logger` object that can be
  used as a regular logger with additional structured data support:

  ```ruby
  Sentry.logger.info("User logged in", user_id: 123)

  Sentry.logger.error("Failed to process payment",
    transaction_id: "tx_123",
    error_code: "PAYMENT_FAILED"
  )
  ```

  You can also use message templates with positional or hash parameters:

  ```ruby
  Sentry.logger.info("User %{name} logged in", name: "Jane Doe")

  Sentry.logger.info("User %s logged in", ["Jane Doe"])
  ```

  Any other arbitrary attributes will be sent as part of the log event payload:

  ```ruby
  # Here `user_id` and `action` will be sent as extra attributes that Sentry Logs UI displays
  Sentry.logger.info("User %{user} logged in", user: "Jane", user_id: 123, action: "create")
  ```

  :warning: When `enable_logs` is `true`, previous `Sentry.logger` should no longer be used for internal SDK
  logging - it was replaced by `Sentry.configuration.sdk_logger` and should be used only by the SDK
  itself and its extensions.

- New configuration option called `active_job_report_on_retry_error` which enables reporting errors on each retry error ([#2617](https://github.com/getsentry/sentry-ruby/pull/2617))

### Bug Fixes

- Gracefully fail on malformed utf-8 breadcrumb message ([#2582](https://github.com/getsentry/sentry-ruby/pull/2582))
  - Fixes [#2376](https://github.com/getsentry/sentry-ruby/issues/2376)
- Fix breadcrumb serialization error message to be an object ([#2584](https://github.com/getsentry/sentry-ruby/pull/2584))
  - Fixes [#2478](https://github.com/getsentry/sentry-ruby/issues/2478)
- Fix compatibility issues with sidekiq-cron 2.2.0 ([#2591](https://github.com/getsentry/sentry-ruby/pull/2591))
- Update sentry-sidekiq to work correctly with Sidekiq 8.0 and its new timestamp format ([#2570](https://github.com/getsentry/sentry-ruby/pull/2570))
- Ensure we capture exceptions after each job retry ([#2597](https://github.com/getsentry/sentry-ruby/pull/2597))

### Internal

- Remove `user_segment` from DSC ([#2586](https://github.com/getsentry/sentry-ruby/pull/2586))
- Replace `logger` with `sdk_logger` ([#2621](https://github.com/getsentry/sentry-ruby/pull/2621))
- `Sentry.logger` is now deprecated when `enable_logs` is turned off. It's original behavior was ported to `Sentry.configuration.sdk_logger`. Please notice that this logger _is internal_ and should only be used for SDK-specific logging needs. ([#2621](https://github.com/getsentry/sentry-ruby/pull/2621))

## 5.23.0

### Features

- Add correct breadcrumb levels for 4xx/5xx response codes ([#2549](https://github.com/getsentry/sentry-ruby/pull/2549))

### Bug Fixes

- Fix argument serialization for ranges that consist of ActiveSupport::TimeWithZone ([#2548](https://github.com/getsentry/sentry-ruby/pull/2548))
- Prevent starting Vernier in nested transactions ([#2528](https://github.com/getsentry/sentry-ruby/pull/2528))
- Fix TypeError when Resque.inline == true ([#2564] https://github.com/getsentry/sentry-ruby/pull/2564)

### Internal

- Use `File.open` in `LineCache` ([#2566](https://github.com/getsentry/sentry-ruby/pull/2566))
- Update java backtrace regexp ([#2567](https://github.com/getsentry/sentry-ruby/pull/2567))
- Stop byteslicing empty strings in breadcrumbs ([#2574](https://github.com/getsentry/sentry-ruby/pull/2574))

### Miscellaneous

- Deprecate `enable_tracing` in favor of `traces_sample_rate = 1.0` [#2535](https://github.com/getsentry/sentry-ruby/pull/2535)

## 5.22.4

### Bug Fixes

- Fix handling of cron with tz in Cron::Job ([#2530](https://github.com/getsentry/sentry-ruby/pull/2530))
- Revert "[rails] support string errors in error reporter (#2464)" ([#2533](https://github.com/getsentry/sentry-ruby/pull/2533))
- Removed unnecessary warning about missing `stackprof` when Vernier is configured as the profiler ([#2537](https://github.com/getsentry/sentry-ruby/pull/2537))
- Fix regression with CheckInEvent in before_send ([#2541](https://github.com/getsentry/sentry-ruby/pull/2541))
  - Fixes [#2540](https://github.com/getsentry/sentry-ruby/issues/2540)

### Internal

- Introduced `Configuration#validate` to validate configuration in `Sentry.init` block ([#2538](https://github.com/getsentry/sentry-ruby/pull/2538))
- Introduced `Sentry.dependency_installed?` to check if a 3rd party dependency is available ie `Sentry.dependency_installed?(:Vernier)` ([#2542](https://github.com/getsentry/sentry-ruby/pull/2542))

## 5.22.3

### Bug Fixes

- Accept Hash in `before_send*` callbacks again ([#2529](https://github.com/getsentry/sentry-ruby/pull/2529))
  - Fixes [#2526](https://github.com/getsentry/sentry-ruby/issues/2526)

## 5.22.2

### Features

- Improve the accuracy of duration calculations in cron jobs monitoring ([#2471](https://github.com/getsentry/sentry-ruby/pull/2471))
- Use attempt_threshold to skip reporting on first N attempts ([#2503](https://github.com/getsentry/sentry-ruby/pull/2503))
- Support `code.namespace` for Ruby 3.4+ stacktraces ([#2506](https://github.com/getsentry/sentry-ruby/pull/2506))

### Bug Fixes

- Default to `internal_error` error type for OpenTelemetry spans [#2473](https://github.com/getsentry/sentry-ruby/pull/2473)
- Improve `before_send` and `before_send_transaction`'s return value handling ([#2504](https://github.com/getsentry/sentry-ruby/pull/2504))
- Fix a crash when calling `Sentry.get_main_hub` in a trap context ([#2510](https://github.com/getsentry/sentry-ruby/pull/2510))
- Use `URI::RFC2396_PARSER.escape` explicitly to remove warning logs to stderr ([#2509](https://github.com/getsentry/sentry-ruby/pull/2509))

### Internal

- Test Ruby 3.4 in CI ([#2506](https://github.com/getsentry/sentry-ruby/pull/2506))
- Upgrade actions workflows versions ([#2506](https://github.com/getsentry/sentry-ruby/pull/2506))
- Stop relying on fugit ([#2519](https://github.com/getsentry/sentry-ruby/pull/2519))

## 5.22.1

### Bug Fixes

- Safe-navigate to session flusher [#2396](https://github.com/getsentry/sentry-ruby/pull/2396)
- Fix latency related nil error for Sidekiq Queues Module span data [#2486](https://github.com/getsentry/sentry-ruby/pull/2486)
  - Fixes [#2485](https://github.com/getsentry/sentry-ruby/issues/2485)

## 5.22.0

:warning: Support for Queues tracking for ActiveJob required changing `op` in transaction context from "queue.sidekiq" to "queue.process". If you rely on this value (e.g. for sampling as described [here](https://docs.sentry.io/platforms/ruby/guides/sidekiq/configuration/sampling/#setting-a-sampling-function)), then you need to update your configuration accordingly.

### Features

- Add `include_sentry_event` matcher for RSpec [#2424](https://github.com/getsentry/sentry-ruby/pull/2424)
- Add support for Sentry Cache instrumentation, when using Rails.cache [#2380](https://github.com/getsentry/sentry-ruby/pull/2380)
  Note: MemoryStore and FileStore require Rails 8.0+
- Add support for Queue Instrumentation for Sidekiq. [#2403](https://github.com/getsentry/sentry-ruby/pull/2403)
- Add support for string errors in error reporter ([#2464](https://github.com/getsentry/sentry-ruby/pull/2464))
- Reset `trace_id` and add root transaction for sidekiq-cron [#2446](https://github.com/getsentry/sentry-ruby/pull/2446)
- Add support for Excon HTTP client instrumentation ([#2383](https://github.com/getsentry/sentry-ruby/pull/2383))

### Bug Fixes

- Ignore internal Sidekiq::JobRetry::Handled exception [#2337](https://github.com/getsentry/sentry-ruby/pull/2337)
- Fix Vernier profiler not stopping when already stopped [#2429](https://github.com/getsentry/sentry-ruby/pull/2429)
- Fix `send_default_pii` handling in rails controller spans [#2443](https://github.com/getsentry/sentry-ruby/pull/2443)
  - Fixes [#2438](https://github.com/getsentry/sentry-ruby/issues/2438)
- Fix `RescuedExceptionInterceptor` to handle an empty configuration [#2428](https://github.com/getsentry/sentry-ruby/pull/2428)
- Add mutex sync to `SessionFlusher` aggregates [#2469](https://github.com/getsentry/sentry-ruby/pull/2469)
  - Fixes [#2468](https://github.com/getsentry/sentry-ruby/issues/2468)
- Fix sentry-rails' backtrace cleaner issues ([#2475](https://github.com/getsentry/sentry-ruby/pull/2475))
  - Fixes [#2472](https://github.com/getsentry/sentry-ruby/issues/2472)

## 5.21.0

### Features

- Experimental support for multi-threaded profiling using [Vernier](https://github.com/jhawthorn/vernier) ([#2372](https://github.com/getsentry/sentry-ruby/pull/2372))

  You can have much better profiles if you're using multi-threaded servers like Puma now by leveraging Vernier.
  To use it, first add `vernier` to your `Gemfile` and make sure it is loaded before `sentry-ruby`.

  ```ruby
  # Gemfile

  gem 'vernier'
  gem 'sentry-ruby'
  ```

  Then, set a `profiles_sample_rate` and the new `profiler_class` configuration in your sentry initializer to use the new profiler.

  ```ruby
  # config/initializers/sentry.rb

  Sentry.init do |config|
    # ...
    config.profiles_sample_rate = 1.0
    config.profiler_class = Sentry::Vernier::Profiler
  end
  ```

### Internal

- Profile items have bigger size limit now ([#2421](https://github.com/getsentry/sentry-ruby/pull/2421))
- Consistent string freezing ([#2422](https://github.com/getsentry/sentry-ruby/pull/2422))

## 5.20.1

### Bug Fixes

- Skip `rubocop.yml` in `spec.files` ([#2420](https://github.com/getsentry/sentry-ruby/pull/2420))

## 5.20.0

- Add support for `$SENTRY_DEBUG` and `$SENTRY_SPOTLIGHT` ([#2374](https://github.com/getsentry/sentry-ruby/pull/2374))
- Support human readable intervals in `sidekiq-cron` ([#2387](https://github.com/getsentry/sentry-ruby/pull/2387))
- Set default app dirs pattern ([#2390](https://github.com/getsentry/sentry-ruby/pull/2390))
- Add new `strip_backtrace_load_path` boolean config (default true) to enable disabling load path stripping ([#2409](https://github.com/getsentry/sentry-ruby/pull/2409))

### Bug Fixes

- Fix error events missing a DSC when there's an active span ([#2408](https://github.com/getsentry/sentry-ruby/pull/2408))
- Verifies presence of client before adding a breadcrumb ([#2394](https://github.com/getsentry/sentry-ruby/pull/2394))
- Fix `Net:HTTP` integration for non-ASCII URI's ([#2417](https://github.com/getsentry/sentry-ruby/pull/2417))
- Prevent Hub from having nil scope and client ([#2402](https://github.com/getsentry/sentry-ruby/pull/2402))

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
- Make sure `sending_allowed?` is respected irrespective of spotlight configuration ([#2231](https://github.com/getsentry/sentry-ruby/pull/2231))
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

- Implement proper flushing logic on `close` for Client Reports and Sessions [#2206](https://github.com/getsentry/sentry-ruby/pull/2206)
- Support cron with timezone for `sidekiq-scheduler` patch [#2209](https://github.com/getsentry/sentry-ruby/pull/2209)
  - Fixes [#2187](https://github.com/getsentry/sentry-ruby/issues/2187)
- Add `Cron::Configuration` object that holds defaults for all `MonitorConfig` objects [#2211](https://github.com/getsentry/sentry-ruby/pull/2211)

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
- Consolidate HTTP span data conventions with OpenTelemetry with `Sentry::Span::DataConventions` [#2093](https://github.com/getsentry/sentry-ruby/pull/2093)
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
- Skip private \_config context in Sidekiq 7+ [#1967](https://github.com/getsentry/sentry-ruby/pull/1967)
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

- Avoid causing NoMethodError for Sentry.\* calls when the SDK is not inited [#1713](https://github.com/getsentry/sentry-ruby/pull/1713)
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
