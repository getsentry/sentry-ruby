require 'spec_helper'

RSpec.describe Sentry::Sidekiq::EventErrorHandler do
  before do
    perform_basic_setup
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:context) do
    {
      "args" => [true, true],
      "class" => "HardWorker",
      "created_at" => 1_474_922_824.910579,
      "enqueued_at" => 1_474_922_824.910665,
      "error_class" => "RuntimeError",
      "error_message" => "a wild exception appeared",
      "failed_at" => 1_474_922_825.158953,
      "jid" => "701ed9cfa51c84a763d56bc4",
      "queue" => "default",
      "retry" => true,
      "retry_count" => 0
    }
  end

  it "ignores jobs in deference to CleanupMiddleware" do
    exception = build_exception

    subject.call(exception, context)

    expect(transport.events.count).to eq(0)
  end

  it "fires for lifecycle events" do
    exception = build_exception

    subject.call(
      exception,
      context: "Exception during Sidekiq lifecycle event.",
      event: :startup
    )

    expect(transport.events.count).to eq(1)
  end
end
