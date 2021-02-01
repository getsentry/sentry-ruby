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

    after do
      described_class.unsubscribe_tracing_events
      described_class.remove_active_support_notifications_patch
    end

    it "records transaction with exception" do
      get "/posts"

      expect(transport.events.count).to eq(2)

      event = transport.events.first.to_hash
      transaction = transport.events.last.to_hash

      expect(event.dig(:contexts, :trace, :trace_id).length).to eq(32)
      expect(event.dig(:contexts, :trace, :trace_id)).to eq(transaction.dig(:contexts, :trace, :trace_id))

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("rails.request")
      parent_span_id = transaction.dig(:contexts, :trace, :span_id)
      expect(transaction[:spans].count).to eq(2)

      first_span = transaction[:spans][0]
      expect(first_span[:op]).to eq("sql.active_record")
      expect(first_span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(first_span[:parent_span_id]).to eq(parent_span_id)

      # this is to make sure we calculate the timestamp in the correct scale (second instead of millisecond)
      expect(first_span[:timestamp] - first_span[:start_timestamp]).to be_between(10.0 / 1_000_000, 10.0 / 1000)

      second_span = transaction[:spans][1]
      expect(second_span[:op]).to eq("process_action.action_controller")
      expect(second_span[:description]).to eq("PostsController#index")
      expect(second_span[:parent_span_id]).to eq(parent_span_id)
    end

    it "records transaction alone" do
      p = Post.create!

      get "/posts/#{p.id}"

      expect(transport.events.count).to eq(1)

      transaction = transport.events.last.to_hash

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("rails.request")
      parent_span_id = transaction.dig(:contexts, :trace, :span_id)
      expect(transaction[:spans].count).to eq(3)

      first_span = transaction[:spans][0]
      expect(first_span[:op]).to eq("sql.active_record")
      expect(first_span[:description].squeeze("\s")).to eq(
        'SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? LIMIT ?'
      )
      expect(first_span[:parent_span_id]).to eq(parent_span_id)

      # this is to make sure we calculate the timestamp in the correct scale (second instead of millisecond)
      expect(first_span[:timestamp] - first_span[:start_timestamp]).to be_between(10.0 / 1_000_000, 10.0 / 1000)

      last_span = transaction[:spans][2]
      expect(last_span[:op]).to eq("process_action.action_controller")
      expect(last_span[:description]).to eq("PostsController#show")
      expect(last_span[:parent_span_id]).to eq(parent_span_id)
    end

    it "doesn't get messed up by previous exception" do
      get "/exception"

      expect(transport.events.count).to eq(2)

      p = Post.create!
      get "/posts/#{p.id}"

      expect(transport.events.count).to eq(3)

      transaction = transport.events.last.to_hash

      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:transaction]).to eq("PostsController#show")
      second_span = transaction[:spans][2]
      expect(second_span[:description]).to eq("PostsController#show")
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
