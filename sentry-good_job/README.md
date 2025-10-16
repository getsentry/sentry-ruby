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
  config.good_job.report_after_job_retries = false
  config.good_job.report_only_dead_jobs = false
  config.good_job.propagate_traces = true
  config.good_job.include_job_arguments = false
  config.good_job.auto_setup_cron_monitoring = true
  config.good_job.logging_enabled = false
end
```

### Configuration Options

- `report_after_job_retries` (default: `false`): Only report errors after all retry attempts are exhausted
- `report_only_dead_jobs` (default: `false`): Only report errors for jobs that cannot be retried
- `propagate_traces` (default: `true`): Propagate trace headers for distributed tracing
- `include_job_arguments` (default: `false`): Include job arguments in error context (be careful with sensitive data)
- `auto_setup_cron_monitoring` (default: `true`): Automatically set up cron monitoring for scheduled jobs
- `logging_enabled` (default: `false`): Enable logging for the Good Job integration
- `logger` (default: `nil`): Custom logger to use (defaults to Rails.logger when available)

## Usage

### Basic Setup

The integration works automatically once installed. It will:

1. Capture exceptions from ActiveJob workers
2. Set up performance monitoring for job execution
3. Automatically configure cron monitoring for scheduled jobs
4. Preserve user context and trace propagation

### Manual Job Monitoring

You can manually set up monitoring for specific job classes:

```ruby
class MyJob < ApplicationJob
  # The integration will automatically set up monitoring
end
```

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
  sentry_cron_monitor "0 * * * *", timezone: "UTC"
end
```

### Custom Error Handling

The integration respects ActiveJob's retry configuration and will only report errors based on your settings:

```ruby
class MyJob < ApplicationJob
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform
    # This will only be reported to Sentry after 3 attempts if report_after_job_retries is true
    raise "Something went wrong"
  end
end
```

### Debugging and Detailed Logging

For debugging purposes, you can enable detailed logging to see what the integration is doing:

```ruby
Sentry.init do |config|
  config.dsn = 'your-dsn-here'
  
  # Enable detailed logging for debugging
  config.good_job.logging_enabled = true
  config.good_job.logger = Logger.new($stdout)
end
```

This will output detailed information about:
- Job execution start and completion
- Error capture and reporting decisions
- Cron monitoring setup
- Performance metrics collection
- Trace propagation

## Performance Monitoring

When performance monitoring is enabled, the integration will track:

- Job execution time
- Queue latency
- Retry counts
- Job context and metadata

## Error Context

The integration automatically adds relevant context to error reports:

- Job class name
- Job ID
- Queue name
- Execution count
- Enqueued and scheduled timestamps
- Job arguments (if enabled)

## Compatibility

- Ruby 2.4+
- Rails 5.2+
- Good Job 3.0+
- Sentry Ruby SDK 5.28.0+

## Contributing

We welcome contributions! Please see our [contributing guidelines](https://github.com/getsentry/sentry-ruby/blob/master/CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE.txt) file for details.
