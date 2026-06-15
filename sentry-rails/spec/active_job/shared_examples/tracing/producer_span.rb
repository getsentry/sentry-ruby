# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that emits a producer span on enqueue" do
  let(:successful_job) do
    job_fixture do
      def perform; end
    end
  end

  context "with traces_sample_rate = 1.0" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

    it "adds a queue.publish child span to the active parent transaction" do
      within_parent_transaction do
        successful_job.set(queue: "events").perform_later
      end

      parent = transactions.find { |t| t.contexts.dig(:trace, :op) == "test" }
      expect(parent).not_to be_nil

      publish_span = parent.spans.find { |s| s[:op] == "queue.publish" }
      expect(publish_span).not_to be_nil
      expect(publish_span[:description]).to eq(successful_job.name)
      expect(publish_span[:origin]).to eq("auto.queue.active_job")
      expect(publish_span[:data]["messaging.message.id"]).to be_a(String).and(satisfy { |v| !v.empty? })
      expect(publish_span[:data]["messaging.destination.name"]).to eq("events")
      expect(publish_span[:timestamp]).not_to be_nil
    end

    it "does not raise or capture an orphan span when no parent transaction is active" do
      expect { successful_job.perform_later }.not_to raise_error

      orphan_publish = transactions.flat_map(&:spans).find { |s| s[:op] == "queue.publish" }
      expect(orphan_publish).to be_nil
    end
  end

  context "with traces_sample_rate = 0" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 0 } }

    it "does not capture a queue.publish span" do
      within_parent_transaction do
        successful_job.perform_later
      end

      publish_spans = transactions.flat_map(&:spans).select { |s| s[:op] == "queue.publish" }
      expect(publish_spans).to be_empty
    end
  end

  context "when producer-span instrumentation raises" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

    it "still enqueues the job and logs the error instead of breaking perform_later" do
      allow(Sentry).to receive(:with_child_span).and_call_original
      allow(Sentry).to receive(:with_child_span)
        .with(hash_including(op: "queue.publish"))
        .and_raise(StandardError, "boom from instrumentation")
      expect(Sentry.sdk_logger).to receive(:error).with(/producer span/)

      within_parent_transaction do
        expect { successful_job.perform_later }.not_to raise_error
      end

      expect(last_enqueued_payload).not_to be_nil
    end

    it "does not swallow a failure raised by the real enqueue" do
      allow(successful_job.queue_adapter).to receive(:enqueue).and_raise(StandardError, "boom from enqueue")

      within_parent_transaction do
        expect { successful_job.perform_later }.to raise_error(StandardError, /boom from enqueue/)
      end
    end
  end
end
