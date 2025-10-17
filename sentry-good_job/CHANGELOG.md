# Changelog

Individual gem's changelog has been deprecated. Please check the [project changelog](https://github.com/getsentry/sentry-ruby/blob/master/CHANGELOG.md).

## 5.28.0

### Features

- Initial release of sentry-good_job integration
- Automatic error capture for ActiveJob workers using Good Job
- Performance monitoring for job execution
- Automatic cron monitoring setup for scheduled jobs
- Context preservation and trace propagation
- Configurable error reporting options
- Rails integration with automatic setup

### Configuration Options

#### Good Job Specific Options
- `enable_cron_monitors`: Enable cron monitoring for scheduled jobs
- `logging_enabled`: Enable logging for the Good Job integration
- `logger`: Custom logger to use

#### ActiveJob Options (handled by sentry-rails)
- `config.rails.active_job_report_on_retry_error`: Only report errors after all retry attempts are exhausted
- `config.send_default_pii`: Include job arguments in error context

**Note**: The Good Job integration now leverages sentry-rails for core ActiveJob functionality, including trace propagation, user context preservation, and error reporting.

### Integration Features

- Seamless integration with Rails applications
- Automatic setup when Good Job integration is enabled
- Support for both manual and automatic cron monitoring
- Respects ActiveJob retry configuration
- Comprehensive error context and performance metrics
