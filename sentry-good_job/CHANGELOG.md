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

- `report_after_job_retries`: Only report errors after all retry attempts are exhausted
- `report_only_dead_jobs`: Only report errors for jobs that cannot be retried
- `propagate_traces`: Propagate trace headers for distributed tracing
- `include_job_arguments`: Include job arguments in error context
- `auto_setup_cron_monitoring`: Automatically set up cron monitoring for scheduled jobs
- `logging_enabled`: Enable logging for the Good Job integration
- `logger`: Custom logger to use

### Integration Features

- Seamless integration with Rails applications
- Automatic setup when Good Job integration is enabled
- Support for both manual and automatic cron monitoring
- Respects ActiveJob retry configuration
- Comprehensive error context and performance metrics
