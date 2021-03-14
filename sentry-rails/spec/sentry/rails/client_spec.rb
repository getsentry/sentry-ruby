require "spec_helper"

return unless Gem::Version.new(Rails.version) >= Gem::Version.new('5.1.0')

RSpec.describe Sentry::Client, type: :request, retry: 3 do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  before do
    expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(1)
  end

  def send_events
    5.times.map do
      Thread.new { Sentry::Rails.capture_message("msg") }
    end.join
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
      send_events

      sleep(0.5)

      expect(transport.events.count).to eq(5)

      expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(1)
    end
  end

  context "when serialization doesn't trigger ActiveRecord queries" do
    before do
      make_basic_app do |config|
        config.background_worker_threads = 5
      end
    end

    it "doesn't create any extra ActiveRecord connection when sending the event" do
      send_events

      sleep(0.1)

      expect(transport.events.count).to eq(5)

      expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(1)
    end
  end
end
