# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActionViewSubscriber, :subscriber, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  context "when transaction is sampled" do
    before do
      make_basic_app do |config|
        config.traces_sample_rate = 1.0
        config.rails.tracing_subscribers = [described_class]
      end
    end

    it "records view rendering event" do
      get "/view"

      expect(transport.events.count).to eq(1)

      transaction = transport.events.first.to_hash
      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:spans].count).to eq(2)

      # ignore the first span, which is for controller action
      span = transaction[:spans][1]
      expect(span[:op]).to eq("template.render_template.action_view")
      expect(span[:origin]).to eq("auto.template.rails")
      expect(span[:description]).to match(/test_template\.html\.erb/)
      expect(span[:trace_id]).to eq(transaction.dig(:contexts, :trace, :trace_id))
    end
  end

  context "when transaction is not sampled" do
    before do
      make_basic_app
    end

    it "doesn't record spans" do
      transaction = Sentry::Transaction.new(sampled: false, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      get "/view"

      transaction.finish

      expect(transport.events.count).to eq(0)
      expect(transaction.span_recorder.spans).to eq([transaction])
    end
  end
end
