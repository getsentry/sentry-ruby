# frozen_string_literal: true

# Adapter context for the :delayed_job ActiveJob backend.
#
# Composes with "active_job backend harness" to drive delayed_job via its
# ActiveRecord backend, reusing the dummy app's SQLite database (the
# +delayed_jobs+ table lives in spec/dummy/test_rails_app/db/schema.rb).
# No external service is required.
#
# This context deliberately does NOT require sentry-delayed_job. Loading
# it would install delayed_job's own plugin (which emits its own
# transactions / error reporting) and could register DelayedJobAdapter in
# skippable_job_adapters, short-circuiting the AJ extension under test.

# delayed_job 4.2+ ships an ActiveJob adapter that inherits from
# ActiveJob::QueueAdapters::AbstractAdapter, which only exists in Rails
# 7.2+. Requiring delayed_job on older Rails drags that adapter in (the
# railtie pulls it during app initialization), raising NameError, so don't
# even load the gem there. The matching spec file applies the same
# Rails-version guard and skips. RAILS_VERSION isn't defined yet at
# support-load time, so read Rails.version directly.
return if ::Rails.version.to_f < 7.2

begin
  require "delayed_job"
  require "delayed_job_active_record"
rescue LoadError
  # delayed_job isn't bundled on this matrix (e.g. JRuby). The matching
  # spec file rescues the same LoadError and skips, so just don't define
  # the context here.
  return
end

RSpec.shared_context "delayed_job adapter" do
  # Instantiated once. DelayedJobAdapter itself is stateless, but we mirror
  # the other adapter contexts (sidekiq, solid_queue) which memoize a
  # single adapter to avoid per-example churn.
  DELAYED_JOB_ADAPTER_FOR_TEST = ::ActiveJob::QueueAdapters::DelayedJobAdapter.new

  def queue_adapter_for_test
    DELAYED_JOB_ADAPTER_FOR_TEST
  end

  def reset_adapter(_adapter)
    ::Delayed::Job.delete_all
  end

  def drain(at: nil)
    # Drive each enqueued Delayed::Job record straight through
    # +JobWrapper#perform+ (== +ActiveJob::Base.execute+) rather than
    # +Delayed::Worker#work_off+. The worker would swallow the perform
    # exception (recording it on the record and rescheduling via
    # delayed_job's own attempts/max_attempts machinery), but the shared
    # examples rely on the worker exception propagating out of +drain+ and
    # on ActiveJob — not delayed_job — owning retry semantics.
    #
    # Each record is destroyed *before* it runs, the way a real worker
    # reserves a job: a given AJ attempt is one Delayed::Job record that
    # executes exactly once. ActiveJob's +retry_on+ re-enqueues a *fresh*
    # record, which the loop then picks up — so retries cascade within a
    # single drain, and a final, attempt-exhausting raise leaves nothing
    # runnable behind for a subsequent drain to re-run.
    run = lambda do
      loop do
        record = ::Delayed::Job
          .where("run_at IS NULL OR run_at <= ?", Time.current)
          .order(Arel.sql("run_at IS NULL DESC"), :run_at, :id)
          .first
        break unless record

        payload = record.payload_object
        record.destroy
        payload.perform
      end
    end

    # Only wrap in travel_to when the caller explicitly asks for a future
    # time (e.g. the scheduled_at example) — otherwise a nested travel_to
    # from a spec that already called +travel+ would raise.
    at ? travel_to(at, &run) : run.call
  end

  def last_enqueued_payload
    record = ::Delayed::Job.order(:id).last
    return nil if record.nil?

    # delayed_job stores the AJ-on-DelayedJob wrapper (carrying the
    # serialized job_data hash) YAML-encoded in the +handler+ column. The
    # deserialized +payload_object+ is the JobWrapper; +job_data+ is the
    # string-keyed ActiveJob payload (so callers can read
    # +payload["_sentry"]+, +payload["arguments"]+, etc.).
    record.payload_object.job_data
  end
end
