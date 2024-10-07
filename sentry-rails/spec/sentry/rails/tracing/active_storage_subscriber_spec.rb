# frozen_string_literal: true

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
      # make sure AnalyzeJob will be executed immediately
      ActiveStorage::AnalyzeJob.queue_adapter.perform_enqueued_jobs = true

      p = Post.create!
      get "/posts/#{p.id}/attach"

      expect(response).to have_http_status(:ok)
      expect(transport.events.count).to eq(2)

      analysis_transaction = transport.events.first.to_hash
      expect(analysis_transaction[:type]).to eq("transaction")

      if Rails.version.to_f > 6.1
        expect(analysis_transaction[:spans].count).to eq(2)
        expect(analysis_transaction[:spans][0][:op]).to eq("file.service_streaming_download.active_storage")
        expect(analysis_transaction[:spans][0][:origin]).to eq("auto.file.rails")
        expect(analysis_transaction[:spans][1][:op]).to eq("file.analyze.active_storage")
        expect(analysis_transaction[:spans][1][:origin]).to eq("auto.file.rails")
      else
        expect(analysis_transaction[:spans].count).to eq(1)
        expect(analysis_transaction[:spans][0][:op]).to eq("file.service_streaming_download.active_storage")
        expect(analysis_transaction[:spans][0][:origin]).to eq("auto.file.rails")
      end

      request_transaction = transport.events.last.to_hash
      expect(request_transaction[:type]).to eq("transaction")
      expect(request_transaction[:spans].count).to eq(2)

      span = request_transaction[:spans][1]
      expect(span[:op]).to eq("file.service_upload.active_storage")
      expect(span[:origin]).to eq("auto.file.rails")
      expect(span[:description]).to eq("Disk")
      expect(span.dig(:data, :key)).to eq(p.cover.key)
      expect(span[:trace_id]).to eq(request_transaction.dig(:contexts, :trace, :trace_id))
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
