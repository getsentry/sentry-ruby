require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActiveRecordSubscriber, :subscriber do
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

    it "records database query events" do
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      Post.all.to_a

      transaction.finish

      expect(transport.events.count).to eq(1)

      transaction = transport.events.first.to_hash
      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:spans].count).to eq(1)

      span = transaction[:spans][0]
      expect(span[:op]).to eq("db.sql.active_record")
      expect(span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(span[:tags].key?(:cached)).to eq(false)
      expect(span[:trace_id]).to eq(transaction.dig(:contexts, :trace, :trace_id))

      data = span[:data]
      expect(data["db.name"]).to eq("db")
      expect(data["db.system"]).to eq("sqlite3")
    end

    it "records database cached query events", skip: Rails.version.to_f < 5.1 do
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      ActiveRecord::Base.connection.cache do
        Post.all.to_a
        Post.all.to_a # Execute a second time, hitting the query cache
      end

      transaction.finish

      expect(transport.events.count).to eq(1)

      transaction = transport.events.first.to_hash
      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:spans].count).to eq(2)

      cached_query_span = transaction[:spans][1]
      expect(cached_query_span[:op]).to eq("db.sql.active_record")
      expect(cached_query_span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(cached_query_span[:tags]).to include({cached: true})

      data = cached_query_span[:data]
      expect(data["db.name"]).to eq("db")
      expect(data["db.system"]).to eq("sqlite3")
    end
  end

  context "when transaction is not sampled" do
    before do
      make_basic_app
    end

    it "doesn't record spans" do
      transaction = Sentry::Transaction.new(sampled: false, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      Post.all.to_a

      transaction.finish

      expect(transport.events.count).to eq(0)
      expect(transaction.span_recorder.spans).to eq([transaction])
    end
  end
end
