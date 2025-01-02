# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActiveRecordSubscriber, :subscriber do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  context "when transaction is sampled" do
    let(:enable_db_query_source) { true }
    let(:db_query_source_threshold_ms) { 0 }

    before do
      make_basic_app do |config|
        config.traces_sample_rate = 1.0
        config.rails.tracing_subscribers = [described_class]
        config.rails.enable_db_query_source = enable_db_query_source
        config.rails.db_query_source_threshold_ms = db_query_source_threshold_ms
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
      expect(span[:origin]).to eq("auto.db.rails")
      expect(span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(span[:tags].key?(:cached)).to eq(false)
      expect(span[:trace_id]).to eq(transaction.dig(:contexts, :trace, :trace_id))

      data = span[:data]
      expect(data["db.name"]).to include("db")
      expect(data["db.system"]).to eq("sqlite3")
    end

    context "when query source location is avaialble", skip: RUBY_VERSION.to_f < 3.2 || Rails.version.to_f < 7.1 do
      def foo
        Post.all.to_a
      end
      query_line = __LINE__ - 2
      rspec_class = self.name # RSpec::ExampleGroups::[....]

      before do
        transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
        Sentry.get_current_scope.set_span(transaction)

        foo

        transaction.finish
      end

      context "when config.rails.enable_db_query_source is false" do
        let(:enable_db_query_source) { false }

        it "doesn't record query's source location" do
          expect(transport.events.count).to eq(1)

          transaction = transport.events.first.to_hash
          expect(transaction[:type]).to eq("transaction")
          expect(transaction[:spans].count).to eq(1)

          span = transaction[:spans][0]
          data = span[:data]
          expect(data["db.name"]).to include("db")
          expect(data["code.filepath"]).to eq(nil)
          expect(data["code.lineno"]).to eq(nil)
          expect(data["code.function"]).to eq(nil)
        end
      end

      context "when the query takes longer than the threshold" do
        let(:db_query_source_threshold_ms) { 0 }

        it "records query's source location" do
          expect(transport.events.count).to eq(1)

          transaction = transport.events.first.to_hash
          expect(transaction[:type]).to eq("transaction")
          expect(transaction[:spans].count).to eq(1)

          span = transaction[:spans][0]
          data = span[:data]
          expect(data["code.filepath"]).to eq(__FILE__)
          expect(data["code.lineno"]).to eq(query_line)
          expect(data["code.namespace"]).to eq(rspec_class) if RUBY_VERSION.to_f >= 3.4
          expect(data["code.function"]).to eq("foo")
        end
      end

      context "when the query takes shorter than the threshold" do
        let(:db_query_source_threshold_ms) { 1000 }

        it "doesn't record query's source location" do
          expect(transport.events.count).to eq(1)

          transaction = transport.events.first.to_hash
          expect(transaction[:type]).to eq("transaction")
          expect(transaction[:spans].count).to eq(1)

          span = transaction[:spans][0]
          data = span[:data]
          expect(data["db.name"]).to include("db")
          expect(data["code.filepath"]).to eq(nil)
          expect(data["code.lineno"]).to eq(nil)
          expect(data["code.function"]).to eq(nil)
        end
      end
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
      expect(cached_query_span[:origin]).to eq("auto.db.rails")
      expect(cached_query_span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(cached_query_span[:tags]).to include({ cached: true })

      data = cached_query_span[:data]
      expect(data["db.name"]).to include("db")
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
