# frozen_string_literal: true

RSpec.shared_context "active_job backend harness" do |adapter:|
  before do
    make_basic_app
    setup_sentry_test

    @previous_queue_adapter = ::ActiveJob::Base.queue_adapter
    ::ActiveJob::Base.queue_adapter = adapter

    boot_adapter(adapter)
  end

  after do
    reset_adapter(adapter)

    ::ActiveJob::Base.queue_adapter = @previous_queue_adapter

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

  define_method(:drain) do
    case adapter
    when :test
      perform_enqueued_jobs
    else
      raise NotImplementedError, "active_job backend harness has no drain strategy for adapter: #{adapter.inspect}"
    end
  end
end
