# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that isolates Sentry context per worker thread" do
  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  it "creates an isolated hub per worker thread when run concurrently" do
    barrier = Concurrent::CyclicBarrier.new(2)
    results_mutex = Mutex.new
    results = {}

    capture = lambda do |tag|
      hub_id = Thread.current.thread_variable_get(Sentry::THREAD_LOCAL).object_id
      Sentry.get_current_scope.set_tags(job: tag)
      raise "barrier timeout in thread #{tag}" unless barrier.wait(5)
      observed_tag = Sentry.get_current_scope.tags[:job]
      results_mutex.synchronize do
        results[tag] = { hub_id: hub_id, observed_tag: observed_tag }
      end
    end

    job_a = job_fixture { define_method(:perform) { capture.call("A") } }
    job_b = job_fixture { define_method(:perform) { capture.call("B") } }

    Sentry.get_current_scope.set_tags(test_thread: true)

    t_a = worker_thread { job_a.perform_now }
    t_b = worker_thread { job_b.perform_now }
    t_a.join
    t_b.join

    expect(results["A"][:hub_id]).not_to eq(results["B"][:hub_id])
    expect(results["A"][:observed_tag]).to eq("A")
    expect(results["B"][:observed_tag]).to eq("B")

    # The test thread's own scope is unchanged.
    expect(Sentry.get_current_scope.tags[:test_thread]).to be_truthy
    expect(Sentry.get_current_scope.tags).not_to have_key(:job)
  end

  it "restores the prior thread-local hub when the job runs on a thread that already has one" do
    hubs = {}
    job = job_fixture do
      define_method(:perform) do
        hubs[:inside_job] = Thread.current.thread_variable_get(Sentry::THREAD_LOCAL)
      end
    end

    Sentry.get_current_scope  # force the lazy clone so the test thread has a hub
    hubs[:before] = Thread.current.thread_variable_get(Sentry::THREAD_LOCAL)

    job.perform_now

    hubs[:after] = Thread.current.thread_variable_get(Sentry::THREAD_LOCAL)

    expect(hubs[:before]).not_to be_nil

    expect(hubs[:inside_job]).not_to equal(hubs[:before])
    expect(hubs[:after]).to equal(hubs[:before])
  end

  it "restores a stale thread-local hub left by a previous job on the same worker thread" do
    job = job_fixture do
      def perform; end
    end

    hubs = Thread.new do
      stale = Sentry.get_main_hub.clone
      Thread.current.thread_variable_set(Sentry::THREAD_LOCAL, stale)

      job.perform_now

      { stale: stale, after: Thread.current.thread_variable_get(Sentry::THREAD_LOCAL) }
    end.value

    expect(hubs[:after]).to equal(hubs[:stale])
  end
end
