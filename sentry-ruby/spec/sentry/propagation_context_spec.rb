require "spec_helper"

RSpec.describe Sentry::PropagationContext do
  before do
    perform_basic_setup
  end

  let(:scope) { Sentry.get_current_scope }
  let(:subject) { described_class.new(scope) }

  describe "#initialize" do
    it "generates correct attributes" do
      expect(subject.trace_id.length).to eq(32)
      expect(subject.span_id.length).to eq(16)
      expect(subject.parent_span_id).to be_nil
    end
  end

  describe "#get_trace_context" do
    it "generates correct trace context" do
      expect(subject.get_trace_context).to eq({
        trace_id: subject.trace_id,
        span_id: subject.span_id,
        parent_span_id: subject.parent_span_id
      })
    end
  end

  describe "#get_traceparent" do
    it "generates correct traceparent" do
      expect(subject.get_traceparent).to eq("#{subject.trace_id}-#{subject.span_id}")
    end
  end

  describe "#get_baggage" do
    before do
      perform_basic_setup do |config|
        config.environment = "test"
        config.release = "foobar"
        config.traces_sample_rate = 0.5
      end
    end

    it "populates head baggage" do
      baggage = subject.get_baggage

      expect(baggage.mutable).to eq(false)
      expect(baggage.items).to eq({
        "trace_id" => subject.trace_id,
        "sample_rate" => "0.5",
        "environment" => "test",
        "release" => "foobar",
        "public_key" => Sentry.configuration.dsn.public_key
      })
    end
  end

  describe "#get_dynamic_sampling_context" do
    it "generates DSC from baggage" do
      expect(subject.get_dynamic_sampling_context).to eq(subject.get_baggage.dynamic_sampling_context)
    end
  end
end
