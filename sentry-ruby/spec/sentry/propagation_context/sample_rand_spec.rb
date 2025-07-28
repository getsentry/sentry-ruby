# frozen_string_literal: true

RSpec.describe Sentry::PropagationContext do
  before do
    perform_basic_setup
  end

  let(:scope) { Sentry.get_current_scope }

  describe "sample_rand integration" do
    describe "#initialize" do
      it "generates sample_rand when no incoming trace" do
        context = described_class.new(scope)

        expect(context.sample_rand).to be_a(Float)
        expect(context.sample_rand).to be >= 0.0
        expect(context.sample_rand).to be < 1.0
      end

      it "generates deterministic sample_rand from trace_id" do
        context1 = described_class.new(scope)
        context2 = described_class.new(scope)

        # Different contexts should have different trace_ids and thus different sample_rand
        expect(context1.sample_rand).not_to eq(context2.sample_rand)

        # But same trace_id should generate same sample_rand
        trace_id = context1.trace_id
        allow(Sentry::Utils).to receive(:uuid).and_return(trace_id)
        context3 = described_class.new(scope)

        expect(context3.sample_rand).to eq(context1.sample_rand)
      end

      context "with incoming trace" do
        let(:env) do
          {
            "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
            "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=0.123456"
          }
        end

        it "uses sample_rand from incoming baggage" do
          context = described_class.new(scope, env)

          expect(context.sample_rand).to eq(0.123456)
          expect(context.incoming_trace).to be true
        end
      end

      context "with incoming trace but no sample_rand in baggage" do
        let(:env) do
          {
            "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
            "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rate=0.5"
          }
        end

        it "generates sample_rand based on sampling decision" do
          context = described_class.new(scope, env)

          expect(context.sample_rand).to be_a(Float)
          expect(context.sample_rand).to be >= 0.0
          expect(context.sample_rand).to be < 1.0
          expect(context.incoming_trace).to be true

          # For sampled=true and sample_rate=0.5, sample_rand should be < 0.5
          expect(context.sample_rand).to be < 0.5
        end

        it "is deterministic for same trace" do
          context1 = described_class.new(scope, env)
          context2 = described_class.new(scope, env)

          expect(context1.sample_rand).to eq(context2.sample_rand)
        end
      end

      context "with incoming trace but no baggage" do
        let(:env) do
          {
            "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1"
          }
        end

        it "generates deterministic sample_rand from trace_id" do
          context = described_class.new(scope, env)

          expect(context.sample_rand).to be_a(Float)
          expect(context.sample_rand).to be >= 0.0
          expect(context.sample_rand).to be < 1.0
          expect(context.incoming_trace).to be true

          # Should be deterministic based on trace_id
          expected = Sentry::Utils::SampleRand.generate_from_trace_id("771a43a4192642f0b136d5159a501700")
          expect(context.sample_rand).to eq(expected)
        end
      end
    end

    describe "#get_baggage" do
      it "includes sample_rand in baggage" do
        context = described_class.new(scope)
        baggage = context.get_baggage

        expect(baggage.items["sample_rand"]).to eq(Sentry::Utils::SampleRand.format(context.sample_rand))
      end

      context "with incoming baggage containing sample_rand" do
        let(:env) do
          {
            "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
            "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=0.654321"
          }
        end

        it "preserves incoming sample_rand in baggage" do
          context = described_class.new(scope, env)
          baggage = context.get_baggage

          expect(baggage.items["sample_rand"]).to eq("0.654321")
        end
      end
    end

    describe "extract_sample_rand_from_baggage" do
      it "extracts valid sample_rand from baggage" do
        baggage = Sentry::Baggage.new({ "sample_rand" => "0.123456" })
        context = described_class.new(scope)

        sample_rand = context.send(:extract_sample_rand_from_baggage, baggage)
        expect(sample_rand).to eq(0.123456)
      end

      it "returns nil for invalid sample_rand" do
        baggage = Sentry::Baggage.new({ "sample_rand" => "1.5" })  # > 1.0 is invalid
        context = described_class.new(scope)

        sample_rand = context.send(:extract_sample_rand_from_baggage, baggage)
        expect(sample_rand).to be_nil
      end

      it "returns nil when no sample_rand in baggage" do
        baggage = Sentry::Baggage.new({ "trace_id" => "abc123" })
        context = described_class.new(scope)

        sample_rand = context.send(:extract_sample_rand_from_baggage, baggage)
        expect(sample_rand).to be_nil
      end

      it "returns nil when baggage is nil" do
        context = described_class.new(scope)

        sample_rand = context.send(:extract_sample_rand_from_baggage, nil)
        expect(sample_rand).to be_nil
      end
    end

    describe "generate_sample_rand" do
      context "with incoming trace and sampling decision" do
        let(:context) do
          ctx = described_class.new(scope)
          ctx.instance_variable_set(:@incoming_trace, true)
          ctx.instance_variable_set(:@parent_sampled, true)
          ctx.instance_variable_set(:@baggage, Sentry::Baggage.new({ "sample_rate" => "0.5" }))
          ctx.instance_variable_set(:@trace_id, "771a43a4192642f0b136d5159a501700")
          ctx
        end

        it "generates sample_rand based on sampling decision" do
          sample_rand = context.send(:generate_sample_rand)

          expect(sample_rand).to be_a(Float)
          expect(sample_rand).to be >= 0.0
          expect(sample_rand).to be < 0.5
        end
      end

      context "without incoming trace" do
        let(:context) do
          ctx = described_class.new(scope)
          ctx.instance_variable_set(:@incoming_trace, false)
          ctx.instance_variable_set(:@trace_id, "771a43a4192642f0b136d5159a501700")
          ctx
        end

        it "generates deterministic sample_rand from trace_id" do
          sample_rand = context.send(:generate_sample_rand)
          expected = Sentry::Utils::SampleRand.generate_from_trace_id("771a43a4192642f0b136d5159a501700")

          expect(sample_rand).to eq(expected)
        end
      end
    end
  end
end
