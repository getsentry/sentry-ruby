require "sentry-ruby"

Sentry.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
end

# Create a config from an interval schedule (every 10 minutes)
monitor_config = Sentry::Cron::MonitorConfig.from_interval(
  1,
  :hour,
  checkin_margin: 15, # Optional check-in margin in minutes
  max_runtime: 15 # Optional max runtime in minutes
)

task :successful_cron do
  # This check-in will tell Sentry that the cron job started and is in-progress.
  # Sentry will expect it to send a :ok check-in within max_runtime minutes.
  check_in_id = Sentry.capture_check_in(
    "rake-task-example",
    :in_progress,
    monitor_config: monitor_config
  )

  puts "rake task is running"

  Sentry.capture_check_in(
    "rake-task-example",
    :ok,
    check_in_id: check_in_id,
    monitor_config: monitor_config
  )
end

task :failed_cron do
  check_in_id = Sentry.capture_check_in(
    "rake-task-example",
    :in_progress,
    monitor_config: monitor_config
  )

  puts "rake task is running"

  # Sending an :error check-in will mark the cron job as errored on Sentry,
  # and this will also create a new Issue on Sentry linked to that cron job.
  Sentry.capture_check_in(
    "rake-task-example",
    :error,
    check_in_id: check_in_id,
    monitor_config: monitor_config
  )
end

task :heartbeat do
  puts "rake task is running"

  # Heartbeat check-in sends :ok status
  # without the parent check_in_id.
  # This will tell Sentry that this cron run was successful.
  Sentry.capture_check_in(
    "rake-task-example",
    :ok,
    monitor_config: monitor_config
  )
end

task :raise_exception do
  check_in_id = Sentry.capture_check_in(
    "rake-task-example",
    :in_progress,
    monitor_config: monitor_config
  )

  puts "rake task is running"

  # If you raise an error within the job, Sentry will report it and link
  # the issue to the cron job. But the job itself will be marked as "in progress"
  # until either your job sends another check-in, or it timeouts.
  raise "This job errored out"
end
