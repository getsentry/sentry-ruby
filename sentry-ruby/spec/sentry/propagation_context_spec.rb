require "spec_helper"

RSpec.describe Sentry::PropagationContext do
  before do
    perform_basic_setup
  end

  let(:scope) { Sentry.get_current_scope }
  let(:subject) { described_class.new(scope) }

  describe "#initialize" do
    it "generates correct attributes without env" do
      expect(subject.trace_id.length).to eq(32)
      expect(subject.span_id.length).to eq(16)
      expect(subject.parent_span_id).to be_nil
      expect(subject.parent_sampled).to be_nil
      expect(subject.baggage).to be_nil
      expect(subject.incoming_trace).to eq(false)
    end

    it "generates correct attributes when incoming sentry-trace and baggage" do
      env = {
        "sentry-trace" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a",
        "baggage" => "other-vendor-value-1=foo;bar;baz, "\
                      "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
                      "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
                      "sentry-sample_rate=0.01337, "\
                      "sentry-user_id=Am%C3%A9lie,  "\
                      "other-vendor-value-2=foo;bar;"
      }

      subject = described_class.new(scope, env)
      expect(subject.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      expect(subject.span_id.length).to eq(16)
      expect(subject.parent_span_id).to eq("7c51afd529da4a2a")
      expect(subject.parent_sampled).to eq(nil)
      expect(subject.incoming_trace).to eq(true)
      expect(subject.baggage).to be_a(Sentry::Baggage)
      expect(subject.baggage.mutable).to eq(false)
      expect(subject.baggage.items).to eq({
        "public_key"=>"49d0f7386ad645858ae85020e393bef3",
        "sample_rate"=>"0.01337",
        "trace_id"=>"771a43a4192642f0b136d5159a501700",
        "user_id"=>"Amélie"
      })
    end

    it "generates correct attributes when incoming HTTP_SENTRY_TRACE and HTTP_BAGGAGE" do
      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a",
        "HTTP_BAGGAGE" => "other-vendor-value-1=foo;bar;baz, "\
                      "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
                      "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
                      "sentry-sample_rate=0.01337, "\
                      "sentry-user_id=Am%C3%A9lie,  "\
                      "other-vendor-value-2=foo;bar;"
      }

      subject = described_class.new(scope, env)
      expect(subject.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      expect(subject.span_id.length).to eq(16)
      expect(subject.parent_span_id).to eq("7c51afd529da4a2a")
      expect(subject.parent_sampled).to eq(nil)
      expect(subject.incoming_trace).to eq(true)
      expect(subject.baggage).to be_a(Sentry::Baggage)
      expect(subject.baggage.mutable).to eq(false)
      expect(subject.baggage.items).to eq({
        "public_key"=>"49d0f7386ad645858ae85020e393bef3",
        "sample_rate"=>"0.01337",
        "trace_id"=>"771a43a4192642f0b136d5159a501700",
        "user_id"=>"Amélie"
      })
    end

    it "generates correct attributes when incoming sentry-trace only (from older SDKs)" do
      env = {
        "sentry-trace" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a"
      }

      subject = described_class.new(scope, env)
      expect(subject.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      expect(subject.span_id.length).to eq(16)
      expect(subject.parent_span_id).to eq("7c51afd529da4a2a")
      expect(subject.parent_sampled).to eq(nil)
      expect(subject.incoming_trace).to eq(true)
      expect(subject.baggage).to be_a(Sentry::Baggage)
      expect(subject.baggage.mutable).to eq(false)
      expect(subject.baggage.items).to eq({})
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
      end
    end

    it "populates head baggage" do
      baggage = subject.get_baggage

      expect(baggage.mutable).to eq(false)
      expect(baggage.items).to eq({
        "trace_id" => subject.trace_id,
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
