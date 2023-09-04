require "spec_helper"

RSpec.describe Sentry::Span do
  let(:hub) do
    client = Sentry::Client.new(Sentry::Configuration.new)
    Sentry::Hub.new(client, Sentry::Scope.new)
  end

  let(:transaction) do
    Sentry::Transaction.new(
      name: "test transaction",
      hub: hub,
      sampled: true
    )
  end

  subject do
    described_class.new(
      transaction: transaction,
      op: "sql.query",
      description: "SELECT * FROM users;",
      status: "ok",
      sampled: true
    )
  end

  describe "#get_trace_context" do
    it "returns correct context data" do
      context = subject.get_trace_context

      expect(context[:op]).to eq("sql.query")
      expect(context[:description]).to eq("SELECT * FROM users;")
      expect(context[:status]).to eq("ok")
      expect(context[:trace_id].length).to eq(32)
      expect(context[:span_id].length).to eq(16)
    end
  end

  describe "#deep_dup" do
    it "copies all the values from the original span" do
      copy = subject.deep_dup

      subject.set_op("foo")
      subject.set_description("bar")

      expect(copy.op).to eq("sql.query")
      expect(copy.description).to eq("SELECT * FROM users;")
      expect(copy.status).to eq("ok")
      expect(copy.trace_id).to eq(subject.trace_id)
      expect(copy.trace_id.length).to eq(32)
      expect(copy.span_id).to eq(subject.span_id)
      expect(copy.span_id.length).to eq(16)
    end
  end

  describe "#to_hash" do
    before do
      subject.set_data("controller", "WelcomeController")
      subject.set_tag("foo", "bar")
    end

    it "returns correct data" do
      hash = subject.to_hash

      expect(hash[:op]).to eq("sql.query")
      expect(hash[:description]).to eq("SELECT * FROM users;")
      expect(hash[:status]).to eq("ok")
      expect(hash[:data]).to eq({ "controller" => "WelcomeController" })
      expect(hash[:tags]).to eq({ "foo" => "bar" })
      expect(hash[:trace_id].length).to eq(32)
      expect(hash[:span_id].length).to eq(16)
    end
  end

  describe "#to_sentry_trace" do
    it "returns correctly-formatted value" do
      sentry_trace = subject.to_sentry_trace

      expect(sentry_trace).to eq("#{subject.trace_id}-#{subject.span_id}-1")
      expect(sentry_trace).to match(Sentry::PropagationContext::SENTRY_TRACE_REGEXP)
    end

    context "without sampled value" do
      subject { described_class.new(transaction: transaction) }

      it "doesn't contain the sampled flag" do
        sentry_trace = subject.to_sentry_trace

        expect(sentry_trace).to eq("#{subject.trace_id}-#{subject.span_id}-")
        expect(sentry_trace).to match(Sentry::PropagationContext::SENTRY_TRACE_REGEXP)
      end
    end
  end

  describe "#to_baggage" do
    before do
      # because initializing transactions requires an active hub
      perform_basic_setup
    end

    subject do
      baggage = Sentry::Baggage.from_incoming_header(
        "other-vendor-value-1=foo;bar;baz, "\
        "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
        "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
        "sentry-sample_rate=0.01337, "\
        "sentry-user_id=Am%C3%A9lie,  "\
        "other-vendor-value-2=foo;bar;"
      )

      Sentry::Transaction.new(hub: Sentry.get_current_hub, baggage: baggage).start_child
    end

    it "propagates sentry baggage values" do
      expect(subject.to_baggage).to eq(
        "sentry-trace_id=771a43a4192642f0b136d5159a501700,"\
        "sentry-public_key=49d0f7386ad645858ae85020e393bef3,"\
        "sentry-sample_rate=0.01337,"\
        "sentry-user_id=Am%C3%A9lie"
      )
    end
  end

  describe "#start_child" do
    before do
      # because initializing transactions requires an active hub
      perform_basic_setup
    end

    it "initializes a new child Span" do
      # create subject span and wait for a sec for making time difference
      subject

      new_span = subject.start_child(op: "sql.query", description: "SELECT * FROM orders WHERE orders.user_id = 1", status: "ok")

      expect(new_span.op).to eq("sql.query")
      expect(new_span.description).to eq("SELECT * FROM orders WHERE orders.user_id = 1")
      expect(new_span.status).to eq("ok")
      expect(new_span.trace_id).to eq(subject.trace_id)
      expect(new_span.span_id).not_to eq(subject.span_id)
      expect(new_span.parent_span_id).to eq(subject.span_id)
      expect(new_span.start_timestamp).not_to eq(subject.start_timestamp)
      expect(new_span.sampled).to eq(true)
    end

    it "gives the child span its transaction" do
      span_1 = subject.start_child

      expect(span_1.transaction).to eq(subject.transaction)

      span_2 = span_1.start_child

      expect(span_2.transaction).to eq(subject.transaction)
    end

    it "initializes a new child Span with explicit span id" do
      span_id = SecureRandom.hex(8)
      new_span = subject.start_child(op: "foo", span_id: span_id)

      expect(new_span.op).to eq("foo")
      expect(new_span.span_id).to eq(span_id)
    end

    context "when the parent span has a span_recorder" do
      subject do
        # inherits the span recorder from the transaction
        Sentry::Transaction.new(hub: Sentry.get_current_hub).start_child
      end

      it "gives the child span its span_recorder" do
        # subject span and the transaction
        expect(subject.span_recorder.spans.count).to eq(2)

        span_1 = subject.start_child

        expect(span_1.span_recorder).to eq(subject.span_recorder)
        expect(subject.span_recorder.spans.count).to eq(3)

        span_2 = span_1.start_child

        expect(span_2.span_recorder).to eq(subject.span_recorder)
        expect(subject.span_recorder.spans.count).to eq(4)
      end
    end
  end

  describe "#with_child_span" do
    it "starts a child span and finish it when the block ends" do
      new_span = subject.with_child_span(op: "sql.query") do |span|
        span.set_data(:child_span, true)
      end

      expect(new_span.op).to eq("sql.query")
      expect(new_span.data).to eq(child_span: true)
      expect(new_span.trace_id).to eq(subject.trace_id)
      expect(new_span.span_id).not_to eq(subject.span_id)
      expect(new_span.parent_span_id).to eq(subject.span_id)
      expect(new_span.start_timestamp).not_to eq(subject.start_timestamp)
      expect(new_span.timestamp).not_to be(nil)
    end

    it "finishes the span even when exception occurs" do
      child_span = nil

      expect do
        subject.with_child_span(op: "sql.query") do |span|
          child_span = span
          1/0
        end
      end.to raise_error(ZeroDivisionError)

      expect(child_span.timestamp).to be_a(Float)
      expect(child_span.status).to eq("internal_error")
    end
  end

  describe "#set_status" do
    it "sets status" do
      subject.set_status("ok")

      expect(subject.status).to eq("ok")
    end
  end

  describe "#set_op" do
    it "sets op" do
      subject.set_op("foo")

      expect(subject.op).to eq("foo")
    end
  end

  describe "#set_description" do
    it "sets description" do
      subject.set_description("bar")

      expect(subject.description).to eq("bar")
    end
  end

  describe "#set_timestamp" do
    it "sets timestamp" do
      time = Time.now.to_f
      subject.set_timestamp(time)

      expect(subject.timestamp).to eq(time)
    end
  end

  describe "#set_http_status" do
    {
      200 => "ok",
      400 => "invalid_argument",
      401 => "unauthenticated",
      403 => "permission_denied",
      404 => "not_found",
      409 => "already_exists",
      429 => "resource_exhausted",
      499 => "cancelled",
      500 => "internal_error",
      501 => "unimplemented",
      503 => "unavailable",
      504 => "deadline_exceeded"
    }.each do |status_code, status|
      it "adds status_code (#{status_code}) to data and sets correct status (#{status})" do
        subject.set_http_status(status_code)

        expect(subject.data["http.response.status_code"]).to eq(status_code)
        expect(subject.status).to eq(status)
      end
    end
  end

  describe "#set_data" do
    it "sets data" do
      subject.set_data(:foo, "bar")

      expect(subject.data).to eq({ foo: "bar" })
    end
  end

  describe "#set_tag" do
    it "sets tag" do
      subject.set_tag(:foo, "bar")

      expect(subject.tags).to eq({ foo: "bar" })
    end
  end
end
