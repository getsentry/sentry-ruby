# frozen_string_literal: true

# Adapter context for the :test ActiveJob backend.
#
# Composes with "active_job backend harness". The harness owns the
# example lifecycle; this context owns everything specific to
# ActiveJob::QueueAdapters::TestAdapter (the Rails-5.2 payload-
# preservation shim, the drain loop, and the enqueued-payload
# accessor).

# Rails 5.2's TestAdapter stores a minimal hash per enqueued job (only
# job class, args, queue) and its +instantiate_job+ recreates jobs via
# +.new(*args)+ — never calling our +deserialize+ override.  That means
# the +_sentry+ payload injected by +serialize+ is silently discarded
# before the consumer ever sees it, breaking distributed-tracing
# propagation.
#
# This adapter subclass calls +job.serialize+ a second time after +super+
# has stored the minimal hash and saves the full output alongside it.
# The drain then drives each job through +ActiveJob::Base.execute(full_payload)+,
# which goes through the normal deserialize → perform_now path and picks
# up the Sentry trace headers and user context that were captured at
# enqueue time.
class Rails52FullPayloadTestAdapter < ::ActiveJob::QueueAdapters::TestAdapter
  def enqueue(job)
    prev = enqueued_jobs.length
    super
    enqueued_jobs.last[:_sentry_full_payload] = job.serialize if enqueued_jobs.length > prev
  end

  def enqueue_at(job, timestamp)
    prev = enqueued_jobs.length
    super
    enqueued_jobs.last[:_sentry_full_payload] = job.serialize if enqueued_jobs.length > prev
  end
end

RSpec.shared_context "test adapter" do
  def queue_adapter_for_test
    # On Rails 5.2 swap in the augmented adapter so the drain can replay
    # the full serialize payload. On Rails 6.0+ returning nil lets
    # TestHelper install its own TestAdapter — the standard path.
    Rails52FullPayloadTestAdapter.new if RAILS_VERSION < 6.0
  end

  def drain(at: nil)
    # Loop until the queue is empty so retries (which re-enqueue during
    # a drain pass) are cascaded through to completion. Both Rails 5.2's
    # manual flush and Rails 6+'s +perform_enqueued_jobs(no block)+
    # operate on a snapshot, so a single pass would only run jobs that
    # existed before draining started.
    loop do
      break if queue_adapter.enqueued_jobs.empty?

      if RAILS_VERSION < 6.1
        # Rails 5.2 and 6.0 both need a manual flush:
        #   - 5.2's +perform_enqueued_jobs+ always requires a block and
        #     only runs jobs enqueued *inside* the block, so it can't
        #     drain a pre-existing queue at all.
        #   - 6.0's +flush_enqueued_jobs+ iterates with +perform_now+
        #     but doesn't remove payloads from +enqueued_jobs+ (the
        #     +delete(payload)+ call was only added in 6.1), so looping
        #     on +enqueued_jobs.empty?+ would spin forever.
        # On 5.2 with Rails52FullPayloadTestAdapter, each payload also
        # carries a +:_sentry_full_payload+ key with the complete
        # serialize output. Drive those jobs through +Base.execute+ so
        # our deserialize override runs and populates +_sentry+
        # before +perform_now+.
        jobs = queue_adapter.enqueued_jobs.dup
        queue_adapter.enqueued_jobs.clear
        jobs.each do |payload|
          if (full = payload[:_sentry_full_payload])
            ::ActiveJob::Base.execute(full)
          else
            send(:instantiate_job, payload).perform_now
          end
        end
      else
        kwargs = at ? { at: at } : {}
        perform_enqueued_jobs(**kwargs)
      end
    end
  end

  def last_enqueued_payload
    payload = queue_adapter.enqueued_jobs.last
    return nil if payload.nil?

    # On Rails < 6.0 we mirror the full serialize output under a side
    # key (see Rails52FullPayloadTestAdapter above). Prefer that when
    # present so callers see the same string-keyed shape they'd see on
    # 6.0+.
    payload[:_sentry_full_payload] || payload
  end
end
