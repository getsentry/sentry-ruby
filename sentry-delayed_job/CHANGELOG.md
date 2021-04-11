# Changelog

## Unreleased

- Add the `report_after_job_retries` configuration option to only report an exception to Sentry if this is the last job's retry after multiple exceptions. [#1364](https://github.com/getsentry/sentry-ruby/pull/1364)

## 4.3.1

- Return delayed job when the SDK is not initialized [#1373](https://github.com/getsentry/sentry-ruby/pull/1373)
  - Fixes [#1334](https://github.com/getsentry/sentry-ruby/issues/1334)

## 4.3.0

- No integration-specific changes

## 4.2.1

- Use ::Rails::Railtie for checking Rails definition [#1287](https://github.com/getsentry/sentry-ruby/pull/1284)
- Convert job id to string to avoid weird syntax error [#1285](https://github.com/getsentry/sentry-ruby/pull/1285)
  - Fixes [#1282](https://github.com/getsentry/sentry-ruby/issues/1282)

## 4.2.0

- First release!
