# frozen_string_literal: true

# Adapter context for the :sidekiq ActiveJob backend.
#
# Composes with "active_job backend harness" to drive Sidekiq via its
# in-memory testing mode. No Redis required: jobs are JSON-round-tripped
# into Sidekiq's class-keyed jobs hash at enqueue time and run in-process
# by drain_all.
#
# This context deliberately does NOT require sentry-sidekiq. Loading
# sentry-sidekiq would install Sidekiq's client/server middleware (which
# emits its own queue.process transactions) and register SidekiqAdapter
# in skippable_job_adapters (which short-circuits the AJ extension under
# test).
begin
  require "sidekiq"
  # Sidekiq 8.1+ deprecates `require "sidekiq/testing"` in favor of
  # `Sidekiq.testing!`, which loads the same test API without the
  # implicit side effect of activating :fake mode at require time.
  if ::Sidekiq.respond_to?(:testing!)
    ::Sidekiq.testing!(:fake)
  else
    require "sidekiq/testing"
  end
rescue LoadError
  # Sidekiq isn't bundled on this matrix (e.g. Rails 5.2). The matching
  # spec file is gated on RAILS_VERSION so it won't try to use this
  # context; skip defining it.
  return
end

RSpec.shared_context "sidekiq adapter" do
  def queue_adapter_for_test
    ::ActiveJob::QueueAdapters::SidekiqAdapter.new
  end

  # Scope fake mode to this example only — the block form of +fake!+
  # uses a per-thread flag that auto-restores when the block exits, so
  # parallel specs and any global Sidekiq mode set elsewhere are left
  # untouched. Wrapping +example.run+ ensures both the +perform_later+
  # (enqueue) and +drain+ (consume) paths see fake mode.
  def with_adapter_active(&block)
    if ::Sidekiq.respond_to?(:testing!)
      ::Sidekiq.testing!(:fake, &block)
    else
      ::Sidekiq::Testing.fake!(&block)
    end
  end

  def drain(at: nil)
    # +drain_all+ loops +while jobs.any?+, so retried jobs (re-enqueued
    # by ActiveJob's +retry_on+ during a drain pass) cascade within a
    # single call. Exceptions raised by the worker propagate out —
    # preserving the +expect { drain }.to raise_error(...)+ semantics
    # the shared examples rely on.
    sidekiq_job_class.drain_all
  end

  def reset_adapter(_adapter)
    sidekiq_job_class.clear_all
  end

  def last_enqueued_payload
    job = ::ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper.jobs.last
    return nil if job.nil?

    # The AJ-on-Sidekiq adapter wraps the AJ payload as the first
    # element of the Sidekiq job's args array (see
    # +Sidekiq::ActiveJob::Wrapper#perform+ /
    # +SidekiqAdapter::JobWrapper#perform+).
    job["args"].first
  end

  private

  # Sidekiq 8 renamed +Sidekiq::Worker+ to +Sidekiq::Job+ (with a
  # back-compat alias). Reach for whichever is canonical on the
  # installed version.
  def sidekiq_job_class
    defined?(::Sidekiq::Job) ? ::Sidekiq::Job : ::Sidekiq::Worker
  end
end
