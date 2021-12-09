# Changelog

Individual gem's changelog has been deprecated. Please check the [project changelog](https://github.com/getsentry/sentry-ruby/blob/master/CHANGELOG.md).

## 4.4.0

### Features

- Allow delayed job's exceptions to be reported to sentry until the last job retry [#1364](https://github.com/getsentry/sentry-ruby/pull/1364)

Add the `report_after_job_retries` configuration option to only report an exception to Sentry if this is the last job's retry after multiple exceptions. 

```ruby
config.delayed_job.report_after_job_retries = true # default is false
```

- Use context for delayed_job's job info [#1395](https://github.com/getsentry/sentry-ruby/pull/1395)

**Before:**

<img width="60%" alt="job info in extra" src="https://user-images.githubusercontent.com/5079556/114307133-de856c00-9b10-11eb-8967-cd0e67e80539.png">

**After:**

<img width="60%" alt="job info in context" src="https://user-images.githubusercontent.com/5079556/114307135-e2b18980-9b10-11eb-9fc4-af885bf0f68d.png">

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
