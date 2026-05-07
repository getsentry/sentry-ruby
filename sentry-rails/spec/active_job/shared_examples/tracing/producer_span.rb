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
end
