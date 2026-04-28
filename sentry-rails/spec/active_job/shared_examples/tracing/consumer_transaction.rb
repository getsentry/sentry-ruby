# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that emits a consumer transaction" do
  let(:successful_job) do
    job_fixture do
      def perform; end
    end
  end

  let(:failing_job) do
    job_fixture do
      def perform
        raise "boom from tracing spec"
      end
    end
  end

  context "with traces_sample_rate = 1.0" do
    before { Sentry.configuration.traces_sample_rate = 1.0 }

    it "captures a successful transaction with name, op, origin, source, and ok status" do
      successful_job.perform_later
      drain

      transaction = sentry_events.find { |e| e.is_a?(Sentry::TransactionEvent) }
      expect(transaction).not_to be_nil

      expect(transaction.transaction).to eq(successful_job.name)
      expect(transaction.transaction_info).to eq(source: :task)
      expect(transaction.contexts.dig(:trace, :op)).to eq("queue.active_job")
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")
      expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
    end

    it "marks the failing transaction internal_error and links the error event by trace_id" do
      expect do
        failing_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from tracing spec/)

      transaction = sentry_events.find { |e| e.is_a?(Sentry::TransactionEvent) }
      error_event = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) }

      expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
      expect(error_event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))
    end
  end

  context "with traces_sample_rate = 0" do
    before { Sentry.configuration.traces_sample_rate = 0 }

    it "does not capture a transaction" do
      expect do
        failing_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from tracing spec/)

      transactions = sentry_events.select { |e| e.is_a?(Sentry::TransactionEvent) }
      expect(transactions).to be_empty
    end
  end
end
