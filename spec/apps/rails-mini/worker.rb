# frozen_string_literal: true

# Background worker entrypoint for the worker-based ActiveJob adapters
# (:sidekiq, :resque, :delayed_job). These adapters enqueue onto an
# external broker (Redis / the DB) and rely on a separate process to
# execute the job. The worker boots the same Rails + Sentry app as the
# web process, so the job's consumer transaction is emitted into the
# shared debug-transport log the e2e suite reads.
#
# :async and :inline run inside the web process and need no worker here.

adapter = ENV.fetch("SENTRY_E2E_ACTIVE_JOB_ADAPTER", "async").to_s.downcase

# The web process owns schema setup; the worker must not recreate the tables
# concurrently. Both processes share the same SQLite file.
ENV["SENTRY_E2E_SKIP_DB_SETUP"] = "true"

# Sidekiq ships its own CLI that boots the app via -r; hand off to it
# directly instead of double-booting Rails in this process. SENTRY_E2E_SKIP_DB_SETUP
# is inherited by the exec'd process, so it skips schema setup too.
if adapter == "sidekiq"
  exec("bundle", "exec", "sidekiq", "-r", "./app.rb", "-c", "2", "-q", "default")
end

require_relative "app"

# Wait for the web process to finish creating the schema before consuming
# jobs (the `posts` table is created in the same block as the others).
60.times do
  break if ActiveRecord::Base.connection.table_exists?(:posts)

  sleep 0.5
end

case adapter
when "resque"
  # Process every queue in-process (no fork) so the Sentry SDK state set
  # up at boot stays intact while the job runs.
  queues = ENV.fetch("QUEUES", "*").split(",")
  ENV["FORK_PER_JOB"] ||= "false"
  worker = Resque::Worker.new(*queues)
  worker.work(ENV.fetch("RESQUE_INTERVAL", "0.5").to_f)
when "delayed_job"
  Delayed::Worker.new(sleep_delay: 0.5, quiet: false).start
else
  # :async and :inline run jobs inside the web process. Stay alive as an
  # idle no-op so this stays a uniform, long-running service under process
  # supervisors (mise `e2e:serve`, Docker Compose) regardless of adapter.
  warn "No external worker needed for adapter: #{adapter.inspect}; idling."
  sleep
end
