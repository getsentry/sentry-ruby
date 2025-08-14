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

        expect(context1.sample_rand).not_to eq(context2.sample_rand)

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

          expect(context.sample_rand).to be < 0.5
        end

        it "is deterministic for same trace" do
          context1 = described_class.new(scope, env)
          context2 = described_class.new(scope, env)

          expect(context1.sample_rand).to eq(context2.sample_rand)
        end
      end

      context "with incoming trace and parent_sampled=false" do
        let(:env) do
          {
            "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-0",
            "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rate=0.5"
          }
        end

        it "generates sample_rand based on unsampled decision" do
          context = described_class.new(scope, env)

          expect(context.sample_rand).to be_a(Float)
          expect(context.sample_rand).to be >= 0.0
          expect(context.sample_rand).to be < 1.0
          expect(context.incoming_trace).to be true
          expect(context.parent_sampled).to be false

          expect(context.sample_rand).to be >= 0.5
        end

        it "is deterministic for same trace" do
          context1 = described_class.new(scope, env)
          context2 = described_class.new(scope, env)

          expect(context1.sample_rand).to eq(context2.sample_rand)
        end

        it "uses parent's explicit unsampled decision instead of falling back to trace_id generation" do
          context = described_class.new(scope, env)

          generator1 = Sentry::Utils::SampleRand.new(trace_id: "771a43a4192642f0b136d5159a501700")
          expected_from_decision = generator1.generate_from_sampling_decision(false, 0.5)

          generator2 = Sentry::Utils::SampleRand.new(trace_id: "771a43a4192642f0b136d5159a501700")
          expected_from_trace_id = generator2.generate_from_trace_id

          expect(context.sample_rand).to eq(expected_from_decision)
          expect(context.sample_rand).not_to eq(expected_from_trace_id)
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

          generator = Sentry::Utils::SampleRand.new(trace_id: "771a43a4192642f0b136d5159a501700")
          expected = generator.generate_from_trace_id
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
  end
end
