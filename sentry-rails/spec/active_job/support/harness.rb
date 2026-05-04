# frozen_string_literal: true

RSpec.shared_context "active_job backend harness" do |adapter:|
  let(:adapter) { adapter }
  let(:configure_sentry) { proc { } }

  around do |example|
    make_basic_app(&configure_sentry)
    setup_sentry_test

    ::ActiveJob::Base.queue_adapter = adapter

    boot_adapter(adapter)

    example.run
  ensure
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
        jobs = queue_adapter.enqueued_jobs.dup
        queue_adapter.enqueued_jobs.clear
        jobs.each { |payload| send(:instantiate_job, payload).perform_now }
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
end
