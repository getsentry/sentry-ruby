require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActionControllerSubscriber, :subscriber, type: :request do
  before do
    make_basic_app
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "records controller action processing event" do
    transaction = Sentry::Transaction.new(sampled: true)
    Sentry.get_current_scope.set_span(transaction)

    get "/world"

    transaction.finish

    expect(transport.events.count).to eq(1)

    transaction = transport.events.first.to_hash
    expect(transaction[:type]).to eq("transaction")
    expect(transaction[:spans].count).to eq(1)

    span = transaction[:spans][0]
    expect(span[:op]).to eq("process_action.action_controller")
    expect(span[:description]).to eq("HelloController#world")
    expect(span[:trace_id]).to eq(transaction.dig(:contexts, :trace, :trace_id))
  end

  it "doesn't record spans for unsampled transaction" do
    transaction = Sentry::Transaction.new(sampled: false)
    Sentry.get_current_scope.set_span(transaction)

    get "/world"

    transaction.finish

    expect(transport.events.count).to eq(0)
    expect(transaction.span_recorder.spans).to eq([transaction])
  end
end
