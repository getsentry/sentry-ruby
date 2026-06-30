# frozen_string_literal: true

# Adapter context for the :resque ActiveJob backend.
#
# Composes with "active_job backend harness" to drive resque entirely
# in-memory via mock_redis — no live Redis required, mirroring how the
# sidekiq context uses Sidekiq's fake mode. resque-scheduler is loaded so
# the AJ adapter's +enqueue_at+ works; ActiveJob routes both scheduled
# jobs (+wait:+) and +retry_on+ re-enqueues through +enqueue_at+, so the
# delayed schedule has to be functional for the shared retry/scheduled
# examples to pass.
#
# Adapter specs guard on Rails version (some adapters need AbstractAdapter
# from 7.2+) and rescue `LoadError` for gems not bundled in every matrix.
#
return if ::Rails.version.to_f < 7.2

begin
  require "mock_redis"
  require "resque"
  require "resque-scheduler"
rescue LoadError
  # resque/mock_redis isn't bundled on this matrix (e.g. JRuby). The
  # matching spec file rescues the same LoadError and skips, so just
  # don't define the context here.
  return
end

RSpec.shared_context "resque adapter" do
  # ResqueAdapter is stateless; memoized once to mirror the other adapter
  # contexts (sidekiq, solid_queue).
  RESQUE_ADAPTER_FOR_TEST = ::ActiveJob::QueueAdapters::ResqueAdapter.new

  def queue_adapter_for_test
    RESQUE_ADAPTER_FOR_TEST
  end

  # Point resque at a fresh in-memory Redis for every example so no queue,
  # delayed-schedule, or +queues+ set state leaks between examples.
  # Resque memoizes its data store, so reassigning +Resque.redis+ rebuilds
  # it against the new MockRedis.
  def boot_adapter(_adapter)
    ::Resque.redis = ::MockRedis.new
    ::Resque.logger = ::Logger.new(nil)
  end

  def drain(at: nil)
    # resque has no in-process "run everything" helper, so we reserve and
    # perform jobs ourselves. +Resque::Job#perform+ runs the job and
    # re-raises any exception (after its failure hooks), which preserves
    # the +expect { drain }.to raise_error(...)+ semantics the shared
    # examples rely on. ActiveJob — not resque — owns retry: a failing
    # +retry_on+ job re-enqueues itself through the adapter's +enqueue_at+
    # into resque-scheduler's delayed set, so each loop iteration first
    # promotes any now-due delayed jobs back onto their queues before
    # reserving. That cascades retries (and +wait: 0+ re-enqueues) to
    # completion within a single drain.
    run = lambda do
      loop do
        promote_due_delayed_jobs(Time.current)
        job = reserve_next_job
        break if job.nil?

        job.perform
      end
    end

    # Only wrap in travel_to when the caller explicitly asks for a future
    # time (e.g. the scheduled_at example) so that delayed jobs scheduled
    # in the future become due — otherwise a nested travel_to from a spec
    # that already called +travel+ would raise.
    at ? travel_to(at, &run) : run.call
  end

  def last_enqueued_payload
    # The AJ-on-resque adapter wraps the serialized AJ payload as the sole
    # element of the resque job's +args+ (see ResqueAdapter#enqueue /
    # JobWrapper.perform). resque pushes to the tail and pops from the
    # head, so the most recently enqueued job sits at the end of its
    # queue. The shared example that reads this enqueues a single job, so
    # returning the tail of the first non-empty queue is sufficient.
    ::Resque.queues.each do |queue|
      size = ::Resque.size(queue)
      next if size.zero?

      item = ::Resque.peek(queue, size - 1)
      return item["args"].first if item
    end

    nil
  end

  private

  # Move every delayed job whose scheduled timestamp is at or before
  # +up_to+ out of resque-scheduler's delayed set and back onto its
  # destination queue, ready to be reserved.
  def promote_due_delayed_jobs(up_to)
    while (timestamp = ::Resque.next_delayed_timestamp(up_to))
      while (item = ::Resque.next_item_for_timestamp(timestamp))
        klass = ::Resque.constantize(item["class"])
        queue = item["queue"] || ::Resque.queue_from_class(klass)
        ::Resque.enqueue_to(queue, klass, *item["args"])
      end
    end
  end

  # Reserve (pop) the next job from any non-empty queue, or nil when every
  # queue is empty.
  def reserve_next_job
    ::Resque.queues.each do |queue|
      job = ::Resque.reserve(queue)
      return job if job
    end

    nil
  end
end
