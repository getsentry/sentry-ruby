require "spec_helper"

RSpec.describe Sentry::Transaction do
  subject do
    described_class.new(
      op: "sql.query",
      description: "SELECT * FROM users;",
      status: "ok",
      sampled: true,
      parent_sampled: true,
      name: "foo"
    )
  end

  describe ".from_sentry_trace" do
    let(:sentry_trace) { subject.to_sentry_trace }

    it "returns correctly-formatted value" do
      child_transaction = described_class.from_sentry_trace(sentry_trace, op: "child")

      expect(child_transaction.trace_id).to eq(subject.trace_id)
      expect(child_transaction.parent_span_id).to eq(subject.span_id)
      expect(child_transaction.parent_sampled).to eq(true)
      expect(child_transaction.op).to eq("child")
    end
  end

  describe "#set_initial_sample_desicion" do
    before do
      Sentry.init do |config|
        config.dsn = DUMMY_DSN
        config.transport.transport_class = Sentry::DummyTransport
      end
    end

    context "when tracing is not enabled" do
      before do
        allow(Sentry.configuration).to receive(:tracing_enabled?).and_return(false)
      end

      it "sets @sampled to false and return" do
        allow(Sentry.configuration).to receive(:tracing_enabled?).and_return(false)

        transaction = described_class.new(sampled: true)
        transaction.set_initial_sample_desicion
        expect(transaction.sampled).to eq(false)
      end
    end

    context "when tracing is enabled" do
      let(:subject) { described_class.new(op: "rack.request", parent_sampled: true) }

      before do
        allow(Sentry.configuration).to receive(:tracing_enabled?).and_return(true)
      end

      context "when the transaction already has a decision" do
        it "doesn't change it" do
          transaction = described_class.new(sampled: true)
          transaction.set_initial_sample_desicion
          expect(transaction.sampled).to eq(true)

          transaction = described_class.new(sampled: false)
          transaction.set_initial_sample_desicion
          expect(transaction.sampled).to eq(false)
        end
      end

      context "when traces_sampler is not set" do
        before do
          Sentry.configuration.traces_sample_rate = 0.5
        end

        it "uses traces_sample_rate for sampling (positive result)" do
          allow(Random).to receive(:rand).and_return(0.4)
          expect(Sentry.configuration.logger).to receive(:debug).with(
            "[Tracing] Starting <rack.request> transaction"
          )

          subject.set_initial_sample_desicion
          expect(subject.sampled).to eq(true)
        end

        it "uses traces_sample_rate for sampling (negative result)" do
          allow(Random).to receive(:rand).and_return(0.6)
          expect(Sentry.configuration.logger).to receive(:debug).with(
            "[Tracing] Discarding <rack.request> transaction because it's not included in the random sample (sampling rate = 0.5)"
          )

          subject.set_initial_sample_desicion
          expect(subject.sampled).to eq(false)
        end
      end

      context "when traces_sampler is provided" do
        it "ignores the sampler if it's not callable" do
          Sentry.configuration.traces_sampler = ""

          expect do
            subject.set_initial_sample_desicion
          end.not_to raise_error
        end

        it "calls the sampler with sampling_context" do
          sampling_context = {}

          Sentry.configuration.traces_sampler = lambda do |context|
            sampling_context = context
          end

          subject.set_initial_sample_desicion(foo: "bar")

          # transaction_context's sampled attribute will be the old value
          expect(sampling_context[:transaction_context].keys).to eq(subject.to_hash.keys)
          expect(sampling_context[:parent_sampled]).to eq(true)
          expect(sampling_context[:foo]).to eq("bar")
        end

        it "disgards the transaction if generated sample rate is not valid" do
          expect(Sentry.configuration.logger).to receive(:warn).with(
            "[Tracing] Discarding <rack.request> transaction because of invalid sample_rate: foo"
          )

          Sentry.configuration.traces_sampler = -> (_) { "foo" }
          subject.set_initial_sample_desicion

          expect(subject.sampled).to eq(false)
        end

        it "uses the genereted rate for sampling (positive)" do
          expect(Sentry.configuration.logger).to receive(:debug).with(
            "[Tracing] Starting transaction"
          ).exactly(2)

          subject = described_class.new
          Sentry.configuration.traces_sampler = -> (_) { true }
          subject.set_initial_sample_desicion
          expect(subject.sampled).to eq(true)

          subject = described_class.new
          Sentry.configuration.traces_sampler = -> (_) { 1.0 }
          subject.set_initial_sample_desicion
          expect(subject.sampled).to eq(true)
        end

        it "uses the genereted rate for sampling (negative)" do
          expect(Sentry.configuration.logger).to receive(:debug).with(
            "[Tracing] Discarding transaction because traces_sampler returned 0 or false"
          ).exactly(2)

          subject = described_class.new
          Sentry.configuration.traces_sampler = -> (_) { false }
          subject.set_initial_sample_desicion
          expect(subject.sampled).to eq(false)

          subject = described_class.new
          Sentry.configuration.traces_sampler = -> (_) { 0.0 }
          subject.set_initial_sample_desicion
          expect(subject.sampled).to eq(false)
        end
      end
    end
  end

  describe "#to_hash" do
    it "returns correct data" do
      hash = subject.to_hash

      expect(hash[:op]).to eq("sql.query")
      expect(hash[:description]).to eq("SELECT * FROM users;")
      expect(hash[:status]).to eq("ok")
      expect(hash[:trace_id].length).to eq(32)
      expect(hash[:span_id].length).to eq(16)
      expect(hash[:sampled]).to eq(true)
      expect(hash[:parent_sampled]).to eq(true)
      expect(hash[:name]).to eq("foo")
    end
  end

  describe "#finish" do
    before do
      Sentry.init do |config|
        config.dsn = DUMMY_DSN
        config.transport.transport_class = Sentry::DummyTransport
      end
    end

    let(:events) do
      Sentry.get_current_client.transport.events
    end

    it "finishes the transaction, converts it into an Event and send it" do
      subject.finish

      expect(events.count).to eq(1)
      event = events.last.to_hash

      # don't contain itself
      expect(event[:spans]).to be_empty
    end

    context "if the transaction is not sampled" do
      subject { described_class.new(sampled: false) }

      it "doesn't send it" do
        subject.finish

        expect(events.count).to eq(0)
      end
    end

    context "if the transaction doesn't have a name" do
      subject { described_class.new(sampled: true) }

      it "adds a default name" do
        subject.finish

        expect(subject.name).to eq("<unlabeled transaction>")
      end
    end
  end
end
