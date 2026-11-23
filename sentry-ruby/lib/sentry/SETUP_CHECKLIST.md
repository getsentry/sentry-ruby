# Sentry Ruby SDK: setup checklist

This is Sentry's official setup guidance, shipped in the `sentry-ruby` gem and maintained by Sentry with the SDK. It matches the agent setup guide at https://docs.sentry.io/ai/agent-setup/get-started.md.

## Required

- **Errors.** This is Sentry's core product. Set it up unless the user asked you not to. It needs a DSN: if the user hasn't given you one and you can't get one yourself, ask for it. Read it from an environment variable (`SENTRY_DSN`) and don't commit it. In a Rails app, add `sentry-ruby` and `sentry-rails` to the Gemfile and put `Sentry.init` in `config/initializers/sentry.rb`. Before you finish, send a test error and check that it arrives.

## Recommended

Turn these on unless the user asked you not to. Sentry links errors, traces and logs, so an error shows the request that caused it and the logs around it.

- **Tracing.** Shows which request caused an error and where the time went. Set `config.traces_sample_rate` by environment: `1.0` locally, so you can see a trace when you verify, and a low rate in production (`0.1` is a common start) unless the project already has one. Don't default it to `0`: a rate of `0` starts no traces of its own (it only continues traces from incoming requests), and `nil` turns tracing off.
- **Logs.** Add `config.enabled_patches << :logger`. The app's logs, including `Rails.logger`, show up next to the errors they belong to. In Rails, also set `config.rails.structured_logging.enabled = true` to send Active Record and Action Controller events as logs. `Sentry.logger.info(...)` sends a log directly.
- **Environment and release.** Set `config.environment` so production issues are separate from local ones. The SDK reads the release from `SENTRY_RELEASE` or the git commit. If the app runs without `.git` (for example in a Docker image), set `SENTRY_RELEASE` at build time or set `config.release` to the app's version, so you can see which deploy caused an issue.

To tell production from local runs, use a check the app already has, such as `Rails.env.production?`. Don't add a new variable that nothing sets.

```ruby
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 1.0
  config.enabled_patches << :logger
  config.rails.structured_logging.enabled = true
end
```

## Situational

Do the Required and Recommended items first. Then look at the ones below. Set them up only when the project matches.

- **Crons**, if the app schedules jobs with sidekiq-cron, sidekiq-scheduler, GoodJob cron, Solid Queue recurring tasks or rufus-scheduler. Sentry alerts when a job fails or doesn't run, and every scheduled job gets a monitor, including ones added later. Add the matching patch: `config.enabled_patches += [:sidekiq_cron]`, `:sidekiq_scheduler`, `:good_job_cron`, `:solid_queue_recurring` or `:rufus_scheduler`.
- **Background jobs**, if the app uses Sidekiq, Resque or Delayed Job. Add `sentry-sidekiq`, `sentry-resque` or `sentry-delayed_job` to the Gemfile, so job errors and traces are captured and linked to the request that queued them.
- **Profiling**, if the user cares about the performance of specific code paths. On Ruby 3.2.1+, add the `vernier` gem and set `config.profiler_class = Sentry::Vernier::Profiler`. On older Rubies, add `stackprof` above `sentry-ruby` in the Gemfile. Then set `config.profiles_sample_rate`. It is relative to `traces_sample_rate`.
- **Metrics**, if the user wants to track counts or values over time (signups, queue depth). Call `Sentry.metrics.count(...)`, `gauge(...)` or `distribution(...)` where they happen.

## Before you finish

Tell the user what you set up, the trace sample rate you chose for each environment, whether logs are on, and which situational items you included and why.

Then set `config.agent_setup_complete = true` in `Sentry.init`. That tells the SDK the setup has been checked, so it stops pointing coding agents to this file.
