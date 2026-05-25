# frozen_string_literal: true

# Backend-agnostic harness for the common ActiveJob spec suite.
#
# This file contains zero knowledge of any specific queue adapter. Each
# adapter spec composes this shared context with its own adapter shared
# context (e.g. "test adapter", "sidekiq adapter") that fills in the
# adapter-specific hooks below.
#
# Adapter selection goes through ActiveJob::TestHelper's official
# +queue_adapter_for_test+ hook. TestHelper's +before_setup+ reads it
# and installs the returned adapter as Base's +_test_adapter+, which the
# +queue_adapter+ reader prefers over the underlying +_queue_adapter+.
# This avoids fighting with the railtie/dummy-app defaults and keeps the
# harness from reaching past TestHelper into private internals.
RSpec.shared_context "active_job backend harness" do |adapter:|
  let(:adapter) { adapter }
  let(:configure_sentry) { proc { } }

  # Boot the dummy Rails app ONCE per example group. Each +make_basic_app+
  # call creates a new +Rails::Application+ subclass and re-runs every
  # initializer — including Sidekiq's railtie (which appends two entries
  # to +Sidekiq.@config_blocks+) and Rails' route-drawing (which also
  # accumulates). Repeating that for every example caused per-example
  # time to grow ~3× over the run, which is what pushed the
  # Ruby 3.4 + Rails 8.1.3 CI matrix past the 15-min timeout.
  #
  # We reproduce the relevant per-example pieces of the Sentry/Rails
  # railtie's +config.after_initialize+ block below (re-init Sentry,
  # re-activate tracing/structured logging, re-register AJ event
  # handlers) so each example still gets a fresh Sentry configuration.
  before(:all) do
    make_basic_app
  end

  around do |example|
    Sentry.init do |config|
      config.release = "beta"
      config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
      config.include_local_variables = true
      configure_sentry.call(config, ::Rails.application) if configure_sentry
    end

    # Mirror the bits of Sentry::Rails::Railtie's after_initialize hook
    # that need to run AFTER Sentry.init each example — the one-time
    # extensions (controller methods, streaming reporter, backtrace
    # cleanup callback, etc.) were already wired up by the initial
    # make_basic_app in before(:all) and persist for the rest of the
    # group.
    if Sentry.configuration.tracing_enabled? && Sentry.configuration.instrumenter == :sentry
      Sentry::Rails::Tracing.register_subscribers(Sentry.configuration.rails.tracing_subscribers)
      Sentry::Rails::Tracing.subscribe_tracing_events
      Sentry::Rails::Tracing.patch_active_support_notifications
    end

    if Sentry.configuration.rails.structured_logging.enabled? && Sentry.configuration.enable_logs
      Sentry::Rails::StructuredLogging.attach(Sentry.configuration.rails.structured_logging)
    end

    if defined?(Sentry::Rails::ActiveJobExtensions)
      Sentry::Rails::ActiveJobExtensions::SentryReporter.register_event_handlers
    end

    setup_sentry_test

    boot_adapter(adapter)

    with_adapter_active { example.run }
  ensure
    reset_adapter(adapter)
    teardown_sentry_test
  end

  # ActiveJob::TestHelper hook. Returning a non-nil adapter instance
  # causes TestHelper to install it as Base's +_test_adapter+ for the
  # duration of each example. Adapter contexts override this.
  def queue_adapter_for_test
  end

  # Optional block wrapper around +example.run+. The default just yields.
  # Adapter contexts override this when the adapter needs a scoped
  # runtime mode active during enqueue + drain (e.g. wrapping the
  # example in +Sidekiq::Testing.fake!+ so fake mode is scoped per
  # example without touching global state).
  def with_adapter_active(&block)
    yield
  end

  # Per-adapter environment setup hook. Backends extend this when they
  # need to load schemas, start supervisors, or otherwise prepare the
  # environment.
  def boot_adapter(_adapter)
  end

  # Per-adapter environment teardown hook. Backends extend this to
  # truncate tables or otherwise clean up state between examples.
  def reset_adapter(_adapter)
  end

  # Drive the adapter to completion. Each adapter context must override
  # this with a strategy that drains its queue (and any retried/scheduled
  # jobs cascaded by the drain) to completion.
  def drain(at: nil)
    raise NotImplementedError,
          "active_job backend harness has no drain strategy for adapter: #{adapter.inspect}. " \
          "Include the matching adapter shared context (e.g. 'test adapter', 'sidekiq adapter')."
  end

  # Return the most recently enqueued job's serialized payload as a Hash
  # keyed by ActiveJob's stringified field names (so callers can read
  # +payload["_sentry"]+, +payload["arguments"]+, etc.). Each adapter
  # context must override this since the on-the-wire shape differs per
  # backend.
  def last_enqueued_payload
    raise NotImplementedError,
          "active_job backend harness has no last_enqueued_payload accessor for adapter: #{adapter.inspect}. " \
          "Include the matching adapter shared context (e.g. 'test adapter', 'sidekiq adapter')."
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
end
