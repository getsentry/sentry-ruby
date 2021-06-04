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

