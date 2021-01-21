# Changelog

## Unreleased (4.1.5)

- Filter out redundant event/payload from breadcrumbs logger [#1222](https://github.com/getsentry/sentry-ruby/pull/1222)

## 4.1.4

- Don't include headers & request info in tracing span or breadcrumb [#1199](https://github.com/getsentry/sentry-ruby/pull/1199)
- Don't run RescuedExceptionInterceptor unless Sentry is initialized [#1204](https://github.com/getsentry/sentry-ruby/pull/1204)

## 4.1.3

- Remove DelayedJobAdapter from ignored list [#1179](https://github.com/getsentry/sentry-ruby/pull/1179)

## 4.1.2

- Use middleware instead of method override to handle rescued exceptions [#1168](https://github.com/getsentry/sentry-ruby/pull/1168)
  - Fixes [#738](https://github.com/getsentry/sentry-ruby/issues/738)
- Adopt Integrable module [#1177](https://github.com/getsentry/sentry-ruby/pull/1177)

## 4.1.1

- Use stricter dependency declaration [#1159](https://github.com/getsentry/sentry-ruby/pull/1159)

## 4.1.0

- Merge & rename 2 Rack middlewares [#1147](https://github.com/getsentry/sentry-ruby/pull/1147)
  - Fixes [#1153](https://github.com/getsentry/sentry-ruby/pull/1153)
  - Removed `Sentry::Rack::Tracing` middleware and renamed `Sentry::Rack::CaptureException` to `Sentry::Rack::CaptureExceptions`
- Tidy up rails integration [#1150](https://github.com/getsentry/sentry-ruby/pull/1150)
- Check SDK initialization before running integrations [#1151](https://github.com/getsentry/sentry-ruby/pull/1151)
  - Fixes [#1145](https://github.com/getsentry/sentry-ruby/pull/1145)

## 4.0.0

- Only documents update for the official release and no API/feature changes.

## 0.3.0

- Major API changes: [1123](https://github.com/getsentry/sentry-ruby/pull/1123)

## 0.2.0

- Multiple fixes and refactorings
- Tracing support

## 0.1.2

Fix require reference

## 0.1.1

Release test

## 0.1.0

First version

