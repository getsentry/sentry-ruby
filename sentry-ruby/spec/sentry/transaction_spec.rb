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
