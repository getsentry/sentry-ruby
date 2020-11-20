require "spec_helper"

RSpec.describe Sentry::Rails::Tracing, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:event) do
    transport.events.last.to_json_compatible
  end

  after do
    transport.events = []
  end

  context "with traces_sample_rate set" do
    before do
      expect(described_class).to receive(:subscribe_tracing_events).and_call_original

      make_basic_app do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "records transaction" do
      get "/posts"

      expect(transport.events.count).to eq(2)

      event = transport.events.first.to_hash
      transaction = transport.events.last.to_hash

      expect(event.dig(:contexts, :trace, :trace_id).length).to eq(32)
      expect(event.dig(:contexts, :trace, :trace_id)).to eq(transaction.dig(:contexts, :trace, :trace_id))

      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:spans].count).to eq(2)

      first_span = transaction[:spans][0]
      expect(first_span[:op]).to eq("rack.request")
      expect(first_span[:status]).to eq("internal_error")
      expect(first_span[:data]).to eq({ "status_code" => 500 })

      second_span = transaction[:spans][1]
      expect(second_span[:op]).to eq("sql.active_record")
      expect(second_span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(second_span[:parent_span_id]).to eq(first_span[:span_id])
    end
  end

  context "without traces_sample_rate set" do
    before do
      expect(described_class).not_to receive(:subscribe_tracing_events)

      make_basic_app
    end

    it "doesn't record any transaction" do
      get "/posts"

      expect(transport.events.count).to eq(1)
    end
  end
end
