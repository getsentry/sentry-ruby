# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ActiveJob hub isolation through the Rails request stack", type: :request do
  let(:transport) { Sentry.get_current_client.transport }

  before do
    stub_const("InlineJob", Class.new(::ActiveJob::Base) do
      def perform
        Sentry.get_current_scope.set_tags(layer: "job")
        Sentry.capture_message("from-job")
      end
    end)

    make_basic_app do |config|
      config.traces_sample_rate = 1.0
    end
  end

  it "isolates the job's scope from the request's and restores the request hub after the job" do
    get "/inline_job"

    expect(response).to have_http_status(:ok)

    events = transport.events

    job_event = events.find { |e| e.is_a?(Sentry::ErrorEvent) && e.message == "from-job" }
    request_event = events.find { |e| e.is_a?(Sentry::ErrorEvent) && e.message == "from-request-after" }
    consumer_transaction = events.find do |e|
      e.is_a?(Sentry::TransactionEvent) && e.contexts.dig(:trace, :op) == "queue.process"
    end

    expect(job_event).not_to be_nil
    expect(job_event.tags[:layer]).to eq("job")

    expect(consumer_transaction).not_to be_nil
    expect(consumer_transaction.tags[:layer]).to eq("job")

    expect(request_event).not_to be_nil
    expect(request_event.tags[:layer]).to eq("request")
  end
end
