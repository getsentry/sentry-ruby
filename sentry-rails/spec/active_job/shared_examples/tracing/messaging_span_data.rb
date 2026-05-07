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

  it "omits messaging.message.retry.count on the first execution" do
    successful_job.perform_later
    drain

    data = consumer_transaction.contexts.dig(:trace, :data)
    expect(data).not_to have_key("messaging.message.retry.count")
  end

  it "records messaging.message.retry.count = executions - 1 on retried executions" do
    klass = job_fixture do
      def perform; end
    end

    allow_any_instance_of(klass).to receive(:executions).and_return(3)

    klass.perform_later
    drain

    data = consumer_transaction.contexts.dig(:trace, :data)
    expect(data["messaging.message.retry.count"]).to eq(2)
  end

  it "records messaging.message.receive.latency in milliseconds", skip: RAILS_VERSION < 6.1 do
    successful_job.perform_later

    travel(5.seconds, with_usec: true) do
      drain
    end

    latency = consumer_transaction.contexts.dig(:trace, :data, "messaging.message.receive.latency")
    expect(latency).to be_a(Integer)
    expect(latency).to be_within(50).of(5_000)
  end
end
