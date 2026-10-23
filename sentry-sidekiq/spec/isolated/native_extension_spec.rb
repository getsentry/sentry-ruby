# frozen_string_literal: true

require "sentry-ruby"

class NativeEnrichmentExtension < Sentry::JobExtensions::Extension
  def handles?(job)
    job.is_a?(Hash) && job["class"] == "SadWorker"
  end

  def scope_data(job:)
    { tags: { enrichment: "present" } }
  end
end

Sentry.register_job_extension(NativeEnrichmentExtension.new(name: "native_enrichment"))

require "spec_helper"
require "sidekiq/api"

RSpec.describe "Native Sidekiq with an earlier enrichment extension" do
  [nil, 0.0, 1.0].each do |sample_rate|
    it "preserves propagation and native metadata at sample rate #{sample_rate.inspect}" do
      perform_basic_setup { |config| config.traces_sample_rate = sample_rate }
      parent = Sentry.start_transaction(name: "enqueue", op: "test")
      Sentry.get_current_scope.set_span(parent) if parent
      headers = Sentry.get_trace_propagation_headers
      client = Sidekiq::Client.new
      client.middleware { |chain| chain.add Sentry::Sidekiq::SentryContextClientMiddleware }
      jid = client.push("class" => SadWorker, "queue" => "extension", "args" => [], "retry" => false)
      message = Sidekiq.redis { |redis| redis.lpop("queue:extension") }
      job = Sidekiq.load_json(message)
      transport = Sentry.get_current_client.transport

      expect(job["trace_propagation_headers"]).to eq(headers)
      expect(headers.keys).to include("sentry-trace", "baggage")
      parent.finish if parent
      process_work(new_processor, Sidekiq::BasicFetch::UnitOfWork.new("queue:extension", message))

      event = transport.events.find { |entry| entry.is_a?(Sentry::ErrorEvent) }
      expect(event.contexts.dig(:trace, :trace_id)).to eq(headers["sentry-trace"].split("-").first)
      expect(event.tags).to include(queue: "extension", jid: jid, enrichment: "present")
      expect(event.contexts[:sidekiq]).to include("jid" => jid, "queue" => "extension")

      if sample_rate == 1.0
        consumer = transport.events.find { |entry| entry.is_a?(Sentry::TransactionEvent) && entry.transaction == "Sidekiq/SadWorker" }
        expect(consumer.contexts.dig(:trace, :data)).to include("messaging.message.id" => jid, "messaging.destination.name" => "extension")
        producer = transport.events.find { |entry| entry.is_a?(Sentry::TransactionEvent) && entry.transaction == "enqueue" }
        expect(producer.spans.first[:data]).to include("messaging.message.id" => jid, "messaging.destination.name" => "extension")
      end
    end
  end
end
