# frozen_string_literal: true

require "spec_helper"

if RAILS_VERSION >= 7.1 && RUBY_VERSION >= "3.1"
  require "solid_queue"

  RSpec.describe "Sentry + ActiveJob on SolidQueue", type: :job do
    include ActiveSupport::Testing::TimeHelpers
    include_context "active_job backend harness", adapter: :solid_queue

    # Instantiated once. Each SolidQueueAdapter.new registers a
    # SolidQueue.on_worker_stop callback at class-load time (mutating
    # global SolidQueue state), so creating a fresh adapter per example
    # would accumulate callbacks across the run.
    SOLID_QUEUE_ADAPTER_FOR_TEST = ::ActiveJob::QueueAdapters::SolidQueueAdapter.new

    def queue_adapter_for_test
      SOLID_QUEUE_ADAPTER_FOR_TEST
    end

    WORKER_SHARD_COUNT = 4

    def boot_adapter(_adapter)
      Sentry::Rails::Test::Application.load_queue_schema

      install_worker_shards
    end

    # Sets up `WORKER_SHARD_COUNT` independent SQLite databases as AR
    # shards alongside the primary test DB. Each worker thread spawned
    # by `worker_thread` claims its own shard, so concurrent perform_later
    # / drain calls from different threads never contend on the same
    # SQLite file (which would otherwise raise SQLite3::BusyException).
    def install_worker_shards
      base_dir = Sentry::Rails::Test::Application.root_path.join("db")
      worker_paths = (1..WORKER_SHARD_COUNT).map { |i| base_dir.join("queue_worker_#{i}.sqlite3") }

      # Wipe any previous run's files so each spec starts fresh.
      worker_paths.each { |p| File.unlink(p) if File.exist?(p) }

      primary_db = Sentry::Rails::Test::Application.db_path.to_s
      configs = { "primary" => { "adapter" => "sqlite3", "database" => primary_db, "timeout" => 5000 } }
      worker_paths.each_with_index do |path, i|
        configs["worker_#{i + 1}"] = { "adapter" => "sqlite3", "database" => path.to_s, "timeout" => 5000 }
      end

      ActiveRecord::Base.configurations = { "test" => configs }

      shards = { default: { writing: :primary } }
      WORKER_SHARD_COUNT.times { |i| shards[:"worker_#{i + 1}"] = { writing: :"worker_#{i + 1}" } }
      ActiveRecord::Base.connects_to(shards: shards)

      # Load the queue schema into each worker shard so its tables exist.
      WORKER_SHARD_COUNT.times do |i|
        ActiveRecord::Base.connected_to(shard: :"worker_#{i + 1}") do
          load Sentry::Rails::Test::Application.queue_schema_file
        end
      end

      @worker_shard_counter = 0
      @worker_shard_mutex = Mutex.new
    end

    def next_worker_shard
      @worker_shard_mutex.synchronize do
        @worker_shard_counter = (@worker_shard_counter % WORKER_SHARD_COUNT) + 1
        :"worker_#{@worker_shard_counter}"
      end
    end

    def worker_thread(&block)
      shard = next_worker_shard
      Thread.new do
        ActiveRecord::Base.connected_to(shard: shard, &block)
      end
    end

    def reset_adapter(_adapter)
      [
        SolidQueue::ReadyExecution,
        SolidQueue::ClaimedExecution,
        SolidQueue::FailedExecution,
        SolidQueue::BlockedExecution,
        SolidQueue::ScheduledExecution,
        SolidQueue::RecurringExecution,
        SolidQueue::Process,
        SolidQueue::Job
      ].each(&:delete_all)
    end

    def drain(at: nil)
      process = SolidQueue::Process.register(
        kind: "Worker",
        pid: ::Process.pid,
        name: "spec-#{SecureRandom.hex(4)}"
      )

      # Loop until both ready and scheduled tables are empty so that
      # retry_on cascades cleanly: a failing perform pushes the job into
      # SolidQueue::ScheduledExecution (via enqueue_at), which the next
      # iteration promotes to ReadyExecution and claims for execution.
      # A single dispatch+claim pass would only observe the first
      # attempt.
      run = lambda do
        loop do
          SolidQueue::ScheduledExecution.dispatch_next_batch(100)
          ready = SolidQueue::ReadyExecution.claim("*", 100, process.id)
          break if ready.empty? && SolidQueue::ScheduledExecution.none?
          ready.each(&:perform)
        end
      end

      # Only wrap in travel_to when the caller explicitly asks for a future
      # time — otherwise nested travel_to (e.g. from a spec that already
      # called `travel`) raises.
      at ? travel_to(at, &run) : run.call
    end

    def last_enqueued_payload
      SolidQueue::Job.order(:id).last&.arguments
    end

    it_behaves_like "a Sentry-instrumented ActiveJob backend"
    it_behaves_like "an ActiveJob backend that supports distributed tracing"
  end
end
