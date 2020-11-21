require "spec_helper"

RSpec.describe Sentry::Span do
  subject do
    described_class.new(
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
      expect(sentry_trace).to match(Sentry::Transaction::SENTRY_TRACE_REGEXP)
    end

    context "without sampled value" do
      subject { described_class.new }

      it "doesn't contain the sampled flag" do
        sentry_trace = subject.to_sentry_trace

        expect(sentry_trace).to eq("#{subject.trace_id}-#{subject.span_id}-")
        expect(sentry_trace).to match(Sentry::Transaction::SENTRY_TRACE_REGEXP)
      end
    end
  end

  describe "#start_child" do
    it "initializes a new child Span" do
      # create subject span and wait for a sec for making time difference
      subject
      sleep 1

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

    it "records the child span" do
      new_span = subject.start_child(op: "sql.query", description: "SELECT * FROM orders WHERE orders.user_id = 1", status: "ok")

      expect(subject.span_recorder.spans).to include(new_span)
      expect(new_span.span_recorder).to eq(subject.span_recorder)
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

        expect(subject.data["status_code"]).to eq(status_code)
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
