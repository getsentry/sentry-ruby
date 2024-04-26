require "active_job"
require "active_record"
require "delayed_job"
require "delayed_job_active_record"
require "sentry-delayed_job"
# require "logger"

# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
# ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :delayed_jobs do |table|
    table.integer :priority, default: 0, null: false # Allows some jobs to jump to the front of the queue
    table.integer :attempts, default: 0, null: false # Provides for retries, but still fail eventually.
    table.text :handler,                 null: false # YAML-encoded string of the object that will do work
    table.text :last_error                           # reason for last failure (See Note below)
    table.datetime :run_at                           # When to run. Could be Time.zone.now for immediately, or sometime in the future.
    table.datetime :locked_at                        # Set when a client is working on this object
    table.datetime :failed_at                        # Set when all retries have failed (actually, by default, the record is deleted instead)
    table.string :locked_by                          # Who is working on this object (if locked)
    table.string :queue                              # The name of the queue this job is in
    table.timestamps null: true
  end
end

Sentry.init do |config|
  config.breadcrumbs_logger = [:sentry_logger]
  # replace it with your sentry dsn
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
end

class MyJob < ActiveJob::Base
  self.queue_adapter = :delayed_job

  def perform
    raise "foo"
  end
end

MyJob.perform_later

enqueued_job = Delayed::Backend::ActiveRecord::Job.last

begin
  enqueued_job.invoke_job
rescue => e
  puts("active job failed because of \"#{e.message}\"")
end

class Foo
  def bar
    1 / 0
  end
end

Foo.new.delay.bar

enqueued_job = Delayed::Backend::ActiveRecord::Job.last

begin
  enqueued_job.invoke_job
rescue => e
  puts("inline job failed because of \"#{e.message}\"")
end
