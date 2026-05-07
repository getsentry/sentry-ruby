# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that isolates Sentry context per worker thread" do
  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  it "creates an isolated hub per worker thread when run concurrently" do
    job_a = job_fixture do
      def perform
        Sentry.get_current_scope.set_tags(job: "A")
        sleep 0.05
      end
    end

    job_b = job_fixture do
      def perform
        Sentry.get_current_scope.set_tags(job: "B")
        sleep 0.05
      end
    end

    Sentry.get_current_scope.set_tags(test_thread: true)

    thread_a = Thread.new { job_a.perform_later; drain }
    thread_b = Thread.new { job_b.perform_later; drain }
    [thread_a, thread_b].each(&:join)

    txn_a = transactions.find { |t| t.tags[:job] == "A" }
    txn_b = transactions.find { |t| t.tags[:job] == "B" }

    expect(txn_a).not_to be_nil
    expect(txn_b).not_to be_nil
    expect(txn_a.tags[:job]).to eq("A")
    expect(txn_b.tags[:job]).to eq("B")

    # The test thread's own scope is unchanged.
    expect(Sentry.get_current_scope.tags[:test_thread]).to be_truthy
    expect(Sentry.get_current_scope.tags).not_to have_key(:job)
  end
end
