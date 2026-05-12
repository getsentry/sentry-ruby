# frozen_string_literal: true

# Rails 5.2's TestAdapter stores a minimal hash per enqueued job (only job
# class, args, queue) and its instantiate_job recreates jobs via `.new(*args)`
# — never calling our `deserialize` override.  That means the `_sentry`
# payload injected by `serialize` is silently discarded before the consumer
# ever sees it, breaking distributed-tracing propagation.
#
# This adapter subclass calls `job.serialize` a second time after `super` has
# stored the minimal hash and saves the full output alongside it.  The drain
# then drives each job through `ActiveJob::Base.execute(full_payload)`, which
# goes through the normal deserialize → perform_now path and picks up the
# Sentry trace headers and user context that were captured at enqueue time.
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

RSpec.shared_context "active_job backend harness" do |adapter:|
  let(:adapter) { adapter }
  let(:configure_sentry) { proc { } }

  around do |example|
    make_basic_app(&configure_sentry)
    setup_sentry_test

    # Rails 5.2's TestAdapter discards the full serialize output (including the
    # _sentry payload) when deferring jobs.  Use our augmented subclass instead
    # so the drain can replay jobs through the proper deserialize path.
    #
    # NOTE: In Rails 5.2 test specs, ActiveJob::TestHelper installs a
    # _test_adapter on ActiveJob::Base via an outer around hook (before_setup).
    # The queue_adapter class method returns _test_adapter when present, so we
    # must use enable_test_adapter (not queue_adapter=) to override it.
    if RAILS_VERSION < 6.0 && adapter == :test
      @_original_test_adapter = ::ActiveJob::Base._test_adapter
      ::ActiveJob::Base.enable_test_adapter(Rails52FullPayloadTestAdapter.new)
    else
      ::ActiveJob::Base.queue_adapter = adapter
    end

    boot_adapter(adapter)

    example.run
  ensure
    if RAILS_VERSION < 6.0 && adapter == :test
      if @_original_test_adapter
        ::ActiveJob::Base.enable_test_adapter(@_original_test_adapter)
      else
        ::ActiveJob::Base.disable_test_adapter
      end
    end

    reset_adapter(adapter)

    teardown_sentry_test
  end

  def boot_adapter(_adapter)
    # Per-adapter setup hook. Backends extend this when they need to load
    # schemas, start supervisors, or otherwise prepare the environment.
  end

  def reset_adapter(_adapter)
    # Per-adapter teardown hook. Backends extend this to truncate tables
    # or otherwise clean up state between examples.
  end

  def drain(at: nil)
    case adapter
    when :test
      if RAILS_VERSION < 6.0
        # Rails 5.2: perform_enqueued_jobs always requires a block and only runs
        # jobs enqueued *inside* the block. Manually flush already-enqueued jobs.
        # When using Rails52FullPayloadTestAdapter, each payload also carries a
        # :_sentry_full_payload key with the complete serialize output.  Drive
        # those jobs through Base.execute so our deserialize override runs and
        # populates @_sentry_trace_headers / @_sentry_user before perform_now.
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
    else
      raise NotImplementedError, "active_job backend harness has no drain strategy for adapter: #{adapter.inspect}"
    end
  end

  def job_fixture(name = nil, &block)
    name ||= "JobFixture_#{SecureRandom.hex(4)}"
    klass = Class.new(::ActiveJob::Base, &block)
    stub_const(name, klass)
    klass
  end

  def transactions
    sentry_events.select { |e| e.is_a?(Sentry::TransactionEvent) }
  end

  def consumer_transaction
    transactions.find { |t| t.contexts.dig(:trace, :op) == "queue.active_job" }
  end

  def within_parent_transaction(name: "parent.test", op: "test")
    txn = Sentry.start_transaction(name: name, op: op)
    Sentry.get_current_scope.set_span(txn) if txn
    yield(txn)
  ensure
    txn&.finish
  end

  # Hook used by the worker_hub_isolation shared example. The default
  # is a plain Thread.new — adapters that need extra setup (e.g. an
  # isolated database per worker thread, like :solid_queue on SQLite)
  # override this to wrap the block in their isolation scope.
  def worker_thread(&block)
    Thread.new(&block)
  end
end
