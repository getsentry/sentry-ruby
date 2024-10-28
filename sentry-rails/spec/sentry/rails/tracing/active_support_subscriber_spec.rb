# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActiveSupportSubscriber, :subscriber, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  context "when transaction is sampled" do
    before do
      make_basic_app do |config, app|
        config.traces_sample_rate = 1.0
        config.rails.tracing_subscribers = [described_class]
      end
    end

    it "tracks cache write" do
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      Rails.cache.write("my_cache_key", "my_cache_value")
      transaction.finish

      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")

      expect(cache_transaction[:spans].count).to eq(1)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.put")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
    end

    #
    it "tracks cache increment" do
      skip("Tracks on Rails 8.0 for all Cache Stores; Until then only MemCached and Redis Stores.") if Rails.version.to_f < 8.0

      Rails.cache.write("my_cache_key", 0)

      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)
      Rails.cache.increment("my_cache_key")

      transaction.finish

      expect(Rails.cache.read("my_cache_key")).to eq(1)
      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(1)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.put")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
    end

    it "tracks cache decrement" do
      skip("Tracks on Rails 8.0 for all Cache Stores; Until then only MemCached and Redis Stores.") if Rails.version.to_f < 8.0

      Rails.cache.write("my_cache_key", 0)

      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)
      Rails.cache.decrement("my_cache_key")

      transaction.finish

      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(1)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.put")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
    end

    it "tracks cache read" do
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)
      Rails.cache.read("my_cache_key")

      transaction.finish

      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(1)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.get")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
    end

    it "tracks cache delete" do
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      Rails.cache.read("my_cache_key")

      transaction.finish

      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(1)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.get")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
    end
    it "tracks cache prune" do
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)

      Rails.cache.write("my_cache_key", 123, expires_in: 0.seconds)

      Rails.cache.prune(0)

      transaction.finish

      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(2)
      expect(cache_transaction[:spans][1][:op]).to eq("cache.flush")
      expect(cache_transaction[:spans][1][:origin]).to eq("auto.cache.rails")
    end

    it "tracks sets cache hit" do
      skip("cache.hit is unset on Rails 6.0.x.") if Rails.version.to_i == 6

      Rails.cache.write("my_cache_key", "my_cache_value")
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)
      Rails.cache.read("my_cache_key")
      Rails.cache.read("my_cache_key_non_existing")

      transaction.finish
      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(2)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.get")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
      expect(cache_transaction[:spans][0][:data]['cache.key']).to eq(["my_cache_key"])
      expect(cache_transaction[:spans][0][:data]['cache.hit']).to eq(true)

      expect(cache_transaction[:spans][1][:op]).to eq("cache.get")
      expect(cache_transaction[:spans][1][:origin]).to eq("auto.cache.rails")
      expect(cache_transaction[:spans][1][:data]['cache.key']).to eq(["my_cache_key_non_existing"])
      expect(cache_transaction[:spans][1][:data]['cache.hit']).to eq(false)
    end

    it "tracks cache delete" do
      Rails.cache.write("my_cache_key", "my_cache_value")
      transaction = Sentry::Transaction.new(sampled: true, hub: Sentry.get_current_hub)
      Sentry.get_current_scope.set_span(transaction)
      Rails.cache.delete("my_cache_key")

      transaction.finish
      expect(transport.events.count).to eq(1)
      cache_transaction = transport.events.first.to_hash
      expect(cache_transaction[:type]).to eq("transaction")
      expect(cache_transaction[:spans].count).to eq(1)
      expect(cache_transaction[:spans][0][:op]).to eq("cache.remove")
      expect(cache_transaction[:spans][0][:origin]).to eq("auto.cache.rails")
      expect(cache_transaction[:spans][0][:data]['cache.key']).to eq(["my_cache_key"])
    end
  end

  context "when transaction is not sampled" do
    before do
      make_basic_app
    end

    it "doesn't record spans" do
      Rails.cache.write("my_cache_key", "my_cache_value")

      expect(transport.events.count).to eq(0)
    end
  end
end
