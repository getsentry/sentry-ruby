# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that records messaging span data on the consumer transaction" do
  include ActiveSupport::Testing::TimeHelpers

  let(:successful_job) do
    job_fixture do
      def perform; end
    end
  end

  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  it "records messaging.message.id and messaging.destination.name on the consumer transaction" do
    successful_job.set(queue: "critical").perform_later
    drain

    data = consumer_transaction.contexts.dig(:trace, :data)
    expect(data["messaging.message.id"]).to be_a(String).and(satisfy { |v| !v.empty? })
    expect(data["messaging.destination.name"]).to eq("critical")
  end

  it "records messaging.message.retry.count = 0 for non-retryable jobs" do
    successful_job.perform_later
    drain

    data = consumer_transaction.contexts.dig(:trace, :data)
    expect(data["messaging.message.retry.count"]).to eq(0)
  end

  context "when the job is retryable" do
    let(:retryable_job) do
      job_fixture do
        retry_on StandardError, attempts: 3, wait: 0

        def perform; end
      end
    end

    it "records messaging.message.retry.count = 0 on the first execution" do
      retryable_job.perform_later
      drain

      data = consumer_transaction.contexts.dig(:trace, :data)
      expect(data["messaging.message.retry.count"]).to eq(0)
    end

    it "records messaging.message.retry.count across real retried executions", skip: RAILS_VERSION < 6.0 do
      retried_job = job_fixture do
        retry_on StandardError, attempts: 3, wait: 0

        def perform
          raise StandardError, "trigger retry" if executions < 3
        end
      end

      retried_job.perform_later
      drain

      consumer_txns = transactions.select { |t| t.contexts.dig(:trace, :op) == "queue.active_job" }
      retry_counts = consumer_txns.map { |t| t.contexts.dig(:trace, :data, "messaging.message.retry.count") }
      expect(retry_counts).to eq([0, 0, 1])
    end
  end

  it "records messaging.message.receive.latency in milliseconds", skip: RAILS_VERSION < 6.1 do
    successful_job.perform_later

    # Older Rails versions truncate Time.now to whole seconds inside `travel`
    # (no `with_usec:` option until 7.0+), so the measured latency can be up
    # to ~999ms below the travel delta. Widen the tolerance accordingly.
    if RAILS_VERSION > 7.0
      travel(5.seconds, with_usec: true) { drain }
      tolerance = 50
    else
      travel(5.seconds) { drain }
      tolerance = 1100
    end

    latency = consumer_transaction.contexts.dig(:trace, :data, "messaging.message.receive.latency")
    expect(latency).to be_a(Integer)
    expect(latency).to be_within(tolerance).of(5_000)
  end
end
