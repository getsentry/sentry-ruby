require "spec_helper"

RSpec.describe Sentry::Client, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  context "when serialization triggers ActiveRecord queries" do
    before do
      make_basic_app do |config|
        config.background_worker_threads = 5
        # simulate connection being obtained during event serialization
        # this could happen when serializing breadcrumbs
        config.before_send = lambda do |event, hint|
          Post.count
          event
        end
      end
    end

    it "doesn't hold the ActiveRecord connection after sending the event" do
      threads = 5.times.map do |i|
        Thread.new do
          Sentry::Rails.capture_message("msg", hint: { index: i })
        end
      end

      threads.join

      sleep(0.1)

      expect(transport.events.count).to eq(5)

      pool = ActiveRecord::Base.connection_pool
      expect(pool.stat[:busy]).to eq(1)
    end
  end

  context "when doesn't serialization trigger ActiveRecord queries" do
    before do
      make_basic_app do |config|
        config.background_worker_threads = 5
      end
    end

    it "doesn't hold the ActiveRecord connection after sending the event" do
      threads = 5.times.map do |i|
        Thread.new do
          Sentry::Rails.capture_message("msg", hint: { index: i })
        end
      end

      threads.join

      sleep(0.1)

      expect(transport.events.count).to eq(5)

      pool = ActiveRecord::Base.connection_pool
      expect(pool.stat[:busy]).to eq(1)
    end
  end
end
