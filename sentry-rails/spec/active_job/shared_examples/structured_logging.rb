# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that produces structured logs" do
  let(:configure_sentry) do
    proc do |config, _app|
      config.enable_logs = true
      config.rails.structured_logging.enabled = true
      config.rails.structured_logging.subscribers = {
        active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber
      }
    end
  end

  let(:simple_job) do
    job_fixture do
      def perform; end
    end
  end

  it "emits structured log entries for enqueue and perform events" do
    simple_job.perform_later
    drain
    Sentry.get_current_client.flush

    enqueue_log = sentry_logs.find { |log| log[:body]&.include?("Job enqueued") }
    perform_log = sentry_logs.find { |log| log[:body]&.include?("Job performed") }

    expect(enqueue_log).not_to be_nil
    expect(enqueue_log[:level]).to eq("info")
    expect(enqueue_log[:attributes][:job_class][:value]).to eq(simple_job.name)

    expect(perform_log).not_to be_nil
    expect(perform_log[:level]).to eq("info")
    expect(perform_log[:attributes][:job_class][:value]).to eq(simple_job.name)
    expect(perform_log[:attributes][:duration_ms][:value]).to be >= 0
  end
end
