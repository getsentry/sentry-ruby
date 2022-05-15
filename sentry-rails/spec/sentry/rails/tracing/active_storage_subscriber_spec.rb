require "spec_helper"

RSpec.describe Sentry::Rails::Tracing::ActiveStorageSubscriber, :subscriber, type: :request, skip: Rails.version.to_f <= 5.2 do
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

    it "records the upload event" do
      p = Post.create!
      get "/posts/#{p.id}/attach"

      expect(response).to have_http_status(:ok)
      transport.events.each { |e| pp e } # TODO: Remove it once this test is not flaky anymore
      expect(transport.events.count).to eq(1)

      transaction = transport.events.first.to_hash
      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:spans].count).to eq(1)

      span = transaction[:spans][0]
      expect(span[:op]).to eq("service_upload.active_storage")
      expect(span[:description]).to eq("Disk")
      expect(span.dig(:data, :key)).to eq(p.cover.key)
      expect(span[:trace_id]).to eq(transaction.dig(:contexts, :trace, :trace_id))
    end
  end

  context "when transaction is not sampled" do
    before do
      make_basic_app
    end

    it "doesn't record spans" do
      p = Post.create!
      get "/posts/#{p.id}/attach"

      expect(response).to have_http_status(:ok)

      expect(transport.events.count).to eq(0)
    end
  end
end
