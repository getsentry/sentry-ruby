<p align="center">
  <a href="https://sentry.io" target="_blank" align="center">
    <img src="https://sentry-brand.storage.googleapis.com/sentry-logo-black.png" width="280">
  </a>
  <br>
</p>

# sentry-good_job, the Good Job integration for Sentry's Ruby client

---

[![Gem Version](https://img.shields.io/gem/v/sentry-good_job.svg)](https://rubygems.org/gems/sentry-good_job)
![Build Status](https://github.com/getsentry/sentry-ruby/actions/workflows/sentry_good_job_test.yml/badge.svg)
[![Coverage Status](https://img.shields.io/codecov/c/github/getsentry/sentry-ruby/master?logo=codecov)](https://codecov.io/gh/getsentry/sentry-ruby/branch/master)
[![Gem](https://img.shields.io/gem/dt/sentry-good_job.svg)](https://rubygems.org/gems/sentry-good_job/)
[![SemVer](https://api.dependabot.com/badges/compatibility_score?dependency-name=sentry-good_job&package-manager=bundler&version-scheme=semver)](https://dependabot.com/compatibility-score.html?dependency-name=sentry-good_job&package-manager=bundler&version-scheme=semver)

[Documentation](https://docs.sentry.io/platforms/ruby/guides/good_job/) | [Bug Tracker](https://github.com/getsentry/sentry-ruby/issues) | [Forum](https://forum.sentry.io/) | IRC: irc.freenode.net, #sentry

The official Ruby-language client and integration layer for the [Sentry](https://github.com/getsentry/sentry) error reporting API.

## Getting Started

### Install

```ruby
gem "sentry-ruby"
gem "sentry-rails"
gem "good_job"
gem "sentry-good_job"
```

Then you're all set! `sentry-good_job` will automatically capture exceptions from your ActiveJob workers when using Good Job as the backend!

## Features

- **Automatic Error Capture**: Captures exceptions from ActiveJob workers using Good Job
- **Performance Monitoring**: Tracks job execution times and performance metrics
- **Cron Monitoring**: Automatic setup for scheduled jobs with cron monitoring
- **Context Preservation**: Maintains user context and trace propagation across job executions
- **Configurable Reporting**: Control when errors are reported (after retries, only dead jobs, etc.)
- **Rails Integration**: Seamless integration with Rails applications

## Configuration

The integration can be configured through Sentry's configuration:

```ruby
Sentry.init do |config|
  config.dsn = 'your-dsn-here'
  
  # Good Job specific configuration
  config.good_job.enable_cron_monitors = true
  
  # ActiveJob configuration (handled by sentry-rails)
  config.rails.active_job_report_on_retry_error = false
  config.send_default_pii = false

  # Optional: Configure logging for debugging
  config.sdk_logger = Rails.logger
end
```

### Configuration Options

#### Good Job Specific Options

- `enable_cron_monitors` (default: `true`): Enable cron monitoring for scheduled jobs

#### ActiveJob Options (handled by sentry-rails)

- `config.rails.active_job_report_on_retry_error` (default: `false`): Only report errors after all retry attempts are exhausted
- `config.send_default_pii` (default: `false`): Include job arguments in error context (be careful with sensitive data)
- `config.sdk_logger` (default: `nil`): Configure the SDK logger for custom logging needs (general Sentry configuration)

**Note**: The Good Job integration now leverages sentry-rails for core ActiveJob functionality, including trace propagation, user context preservation, and error reporting. This provides better integration and reduces duplication.

## Usage

### Automatic Setup

The integration works automatically once installed. It will:

1. **Capture exceptions** from ActiveJob workers using sentry-rails
2. **Set up performance monitoring** for job execution with enhanced GoodJob-specific metrics
3. **Automatically configure cron monitoring** for scheduled jobs
4. **Preserve user context and trace propagation** across job executions
5. **Add GoodJob-specific context** including queue name, executions, priority, and latency

### Cron Monitoring

For scheduled jobs, cron monitoring is automatically set up based on your Good Job configuration:

```ruby
# config/application.rb
config.good_job.cron = {
  'my_scheduled_job' => {
    class: 'MyScheduledJob',
    cron: '0 * * * *' # Every hour
  }
}
```

You can also manually set up cron monitoring:

```ruby
class MyScheduledJob < ApplicationJob
  include Sentry::Cron::MonitorCheckIns

  sentry_monitor_check_ins(
    slug: "my_scheduled_job",
    monitor_config: Sentry::Cron::MonitorConfig.from_crontab("0 * * * *", timezone: "UTC")
  )
end
```

### Custom Error Handling

The integration respects ActiveJob's retry configuration and will only report errors based on your settings:

```ruby
class MyJob < ApplicationJob
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform
    # This will only be reported to Sentry after 3 attempts if active_job_report_on_retry_error is true
    raise "Something went wrong"
  end
end
```

### Debugging and Detailed Logging

The integration uses the standard Sentry SDK logger (`Sentry.configuration.sdk_logger`) for all logging needs. You can configure this logger to get detailed information about what the integration is doing:

```ruby
Sentry.init do |config|
  config.dsn = 'your-dsn-here'
  
  # Configure the SDK logger for debugging
  config.sdk_logger = Logger.new($stdout)
  config.sdk_logger.level = Logger::DEBUG

  # Or use Rails logger with debug level
  # config.sdk_logger = Rails.logger
  # config.sdk_logger.level = Logger::DEBUG
end
```

#### Log Levels

The integration logs at different levels:
- **INFO**: Integration setup, cron monitoring configuration, job monitoring setup
- **WARN**: Configuration issues, missing job classes, cron parsing errors
- **DEBUG**: Detailed execution flow (when debug level is enabled)

#### What Gets Logged

When logging is enabled, you'll see information about:
- Job execution start and completion
- Error capture and reporting decisions
- Cron monitoring setup and configuration
- Performance metrics collection
- GoodJob-specific context enhancement
- Integration initialization and setup

## Performance Monitoring

When performance monitoring is enabled, the integration will track:

- Job execution time
- Queue latency (GoodJob-specific)
- Retry counts
- Job context and metadata
- GoodJob-specific metrics (queue name, executions, priority)

## Error Context

The integration automatically adds relevant context to error reports:

- Job class name
- Job ID
- Queue name (GoodJob-specific)
- Execution count (GoodJob-specific)
- Priority (GoodJob-specific)
- Enqueued and scheduled timestamps
- Job arguments (if enabled via send_default_pii)
- Latency metrics (GoodJob-specific)

## Compatibility

- Ruby 2.4+
- Rails 5.2+
- Good Job 3.0+
- Sentry Ruby SDK 5.28.0+

## Contributing

We welcome contributions! Please see our [contributing guidelines](https://github.com/getsentry/sentry-ruby/blob/master/CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE.txt) file for details.
