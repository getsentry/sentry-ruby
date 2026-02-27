# frozen_string_literal: true

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
        "sample_rand" => Sentry::Utils::SampleRand.format(subject.sample_rand),
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

  describe ".should_continue_trace?" do
    # Decision matrix:
    # | Baggage org | SDK org | strict | Result       |
    # |-------------|---------|--------|--------------|
    # | 1           | 1       | false  | Continue     |
    # | None        | 1       | false  | Continue     |
    # | 1           | None    | false  | Continue     |
    # | None        | None    | false  | Continue     |
    # | 1           | 2       | false  | Start new    |
    # | 1           | 1       | true   | Continue     |
    # | None        | 1       | true   | Start new    |
    # | 1           | None    | true   | Start new    |
    # | None        | None    | true   | Continue     |
    # | 1           | 2       | true   | Start new    |

    let(:sentry_trace) { "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1" }

    def make_env(sentry_trace:, baggage_org_id: nil)
      baggage_parts = ["sentry-trace_id=771a43a4192642f0b136d5159a501700"]
      baggage_parts << "sentry-org_id=#{baggage_org_id}" if baggage_org_id

      {
        "sentry-trace" => sentry_trace,
        "baggage" => baggage_parts.join(",")
      }
    end

    context "with strict_trace_continuation=false" do
      it "continues when baggage org matches SDK org" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o1.ingest.sentry.io/42"
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end

      it "continues when baggage has no org but SDK has org" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o1.ingest.sentry.io/42"
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: nil)
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end

      it "continues when baggage has org but SDK has no org" do
        perform_basic_setup do |config|
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end

      it "continues when neither has org" do
        perform_basic_setup do |config|
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: nil)
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end

      it "starts new trace when orgs mismatch" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o2.ingest.sentry.io/42"
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(false)
        expect(propagation_context.trace_id).not_to eq("771a43a4192642f0b136d5159a501700")
      end
    end

    context "with strict_trace_continuation=true" do
      it "continues when baggage org matches SDK org" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o1.ingest.sentry.io/42"
          config.strict_trace_continuation = true
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end

      it "starts new trace when baggage has no org but SDK has org" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o1.ingest.sentry.io/42"
          config.strict_trace_continuation = true
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: nil)
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(false)
        expect(propagation_context.trace_id).not_to eq("771a43a4192642f0b136d5159a501700")
      end

      it "starts new trace when baggage has org but SDK has no org" do
        perform_basic_setup do |config|
          config.strict_trace_continuation = true
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(false)
        expect(propagation_context.trace_id).not_to eq("771a43a4192642f0b136d5159a501700")
      end

      it "continues when neither has org" do
        perform_basic_setup do |config|
          config.strict_trace_continuation = true
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: nil)
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end

      it "starts new trace when orgs mismatch" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o2.ingest.sentry.io/42"
          config.strict_trace_continuation = true
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(false)
        expect(propagation_context.trace_id).not_to eq("771a43a4192642f0b136d5159a501700")
      end
    end

    context "with explicit org_id config" do
      it "uses explicit org_id over DSN-parsed org_id" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o1234.ingest.sentry.io/42"
          config.org_id = "9999"
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "1234")
        propagation_context = described_class.new(scope, env)
        # org_id mismatch: baggage has 1234 but SDK effective org_id is 9999
        expect(propagation_context.incoming_trace).to eq(false)
        expect(propagation_context.trace_id).not_to eq("771a43a4192642f0b136d5159a501700")
      end

      it "continues when explicit org_id matches baggage org_id" do
        perform_basic_setup do |config|
          config.dsn = "https://key@o1234.ingest.sentry.io/42"
          config.org_id = "5678"
          config.strict_trace_continuation = false
        end

        env = make_env(sentry_trace: sentry_trace, baggage_org_id: "5678")
        propagation_context = described_class.new(scope, env)
        expect(propagation_context.incoming_trace).to eq(true)
        expect(propagation_context.trace_id).to eq("771a43a4192642f0b136d5159a501700")
      end
    end
  end

  describe ".extract_sentry_trace" do
    it "extracts valid sentry-trace without whitespace" do
      sentry_trace = "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1"
      result = described_class.extract_sentry_trace(sentry_trace)

      expect(result).to eq(["771a43a4192642f0b136d5159a501700", "7c51afd529da4a2a", true])
    end

    it "extracts valid sentry-trace with leading and trailing whitespace" do
      sentry_trace = "  \t771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1\t  "
      result = described_class.extract_sentry_trace(sentry_trace)

      expect(result).to eq(["771a43a4192642f0b136d5159a501700", "7c51afd529da4a2a", true])
    end

    it "extracts sentry-trace without sampled flag" do
      sentry_trace = "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a"
      result = described_class.extract_sentry_trace(sentry_trace)

      expect(result).to eq(["771a43a4192642f0b136d5159a501700", "7c51afd529da4a2a", nil])
    end

    it "returns nil for invalid sentry-trace" do
      expect(described_class.extract_sentry_trace("invalid")).to be_nil
      expect(described_class.extract_sentry_trace("000-000-0")).to be_nil
      expect(described_class.extract_sentry_trace("")).to be_nil
    end

    it "allows whitespace" do
      whitespace = " \t \t \t \t "
      sentry_trace = "#{whitespace}771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1#{whitespace}"
      result = described_class.extract_sentry_trace(sentry_trace)

      expect(result).to eq(["771a43a4192642f0b136d5159a501700", "7c51afd529da4a2a", true])
    end
  end
end
