require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActionViewSubscriber, type: :request do
  before do
    make_basic_app
    Sentry::Rails::Tracing.patch_active_support_notifications
    described_class.subscribe!
  end

  after do
    described_class.unsubscribe!
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "records view rendering event" do
    transaction = Sentry.start_transaction
    Sentry.get_current_scope.set_span(transaction)

    get "/view"

    transaction.finish

    expect(transport.events.count).to eq(1)

    transaction = transport.events.first.to_hash
    expect(transaction[:type]).to eq("transaction")
    expect(transaction[:spans].count).to eq(1)

    span = transaction[:spans][0]
    expect(span[:op]).to eq("render_template.action_view")
    expect(span[:description]).to match(/test_template\.html\.erb/)
    expect(span[:trace_id]).to eq(transaction.dig(:contexts, :trace, :trace_id))
  end
end
