# frozen_string_literal: true

RSpec.describe "Trace propagation" do
  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 0.5

      config.traces_sampler = lambda do |sampling_context|
        parent_sample_rate = sampling_context[:parent_sample_rate]

        if parent_sample_rate
          parent_sample_rate
        else
          0.5
        end
      end
    end
  end

  describe "end-to-end propagated sampling" do
    it "maintains consistent sampling across distributed trace" do
      root_transaction = Sentry.start_transaction(name: "root", op: "http.server")

      Sentry.get_current_scope.set_span(root_transaction)

      headers = Sentry.get_trace_propagation_headers

      expect(headers).to include("sentry-trace", "baggage")
      expect(headers["baggage"]).to include("sentry-sample_rand=")

      baggage = root_transaction.get_baggage
      sample_rand_from_baggage = baggage.items["sample_rand"]

      expect(sample_rand_from_baggage).to match(/\A\d+\.\d{6}\z/)

      sentry_trace = headers["sentry-trace"]
      baggage_header = headers["baggage"]

      child_transaction = Sentry::Transaction.from_sentry_trace(
        sentry_trace,
        baggage: baggage_header
      )

      expect(child_transaction).not_to be_nil

      Sentry.get_current_scope.set_span(child_transaction)

      started_child = Sentry.start_transaction(transaction: child_transaction)

      expect(started_child.sampled).to eq(root_transaction.sampled)
      expect(started_child.effective_sample_rate).to eq(root_transaction.effective_sample_rate)

      child_headers = Sentry.get_trace_propagation_headers

      expect(child_headers["baggage"]).to include("sentry-sample_rand=")

      child_baggage = started_child.get_baggage
      child_sample_rand = child_baggage.items["sample_rand"]

      expect(child_sample_rand).to eq(sample_rand_from_baggage)
    end

    it "handles missing sample_rand gracefully" do
      sentry_trace = "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1"
      baggage_header = "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rate=0.25"

      transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, baggage: baggage_header)

      expect(transaction).not_to be_nil

      expected_sample_rand = Sentry::Utils::SampleRand.generate_from_sampling_decision(
        true,
        0.25,
        "771a43a4192642f0b136d5159a501700"
      )

      expect(expected_sample_rand).to be >= 0.0
      expect(expected_sample_rand).to be < 1.0
      expect(expected_sample_rand).to be < 0.25

      expected_sample_rand2 = Sentry::Utils::SampleRand.generate_from_sampling_decision(
        true, 0.25, "771a43a4192642f0b136d5159a501700"
      )
      expect(expected_sample_rand2).to eq(expected_sample_rand)

      baggage = transaction.get_baggage

      expect(baggage.items).to eq({
        "trace_id" => "771a43a4192642f0b136d5159a501700",
        "sample_rate" => "0.25"
      })
    end

    it "works with PropagationContext for tracing without performance" do
      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
        "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=0.123456"
      }

      scope = Sentry.get_current_scope
      propagation_context = Sentry::PropagationContext.new(scope, env)

      expect(propagation_context.sample_rand).to eq(0.123456)

      baggage = propagation_context.get_baggage
      expect(baggage.items["sample_rand"]).to eq("0.123456")
    end

    it "demonstrates deterministic sampling behavior" do
      trace_id = "771a43a4192642f0b136d5159a501700"

      results = 5.times.map do
        transaction = Sentry::Transaction.new(trace_id: trace_id, hub: Sentry.get_current_hub)
        Sentry.start_transaction(transaction: transaction)
        transaction.sampled
      end

      expect(results.uniq.length).to eq(1)

      sample_rands = 5.times.map do
        transaction = Sentry::Transaction.new(trace_id: trace_id, hub: Sentry.get_current_hub)
        baggage = transaction.get_baggage
        baggage.items["sample_rand"]
      end

      expect(sample_rands.uniq.length).to eq(1)

      expected_sample_rand = Sentry::Utils::SampleRand.format(
        Sentry::Utils::SampleRand.generate_from_trace_id(trace_id)
      )
      expect(sample_rands.first).to eq(expected_sample_rand)
    end

    it "works with custom traces_sampler" do
      sampling_contexts = []

      Sentry.configuration.traces_sampler = lambda do |context|
        sampling_contexts << context
        context[:parent_sample_rate] || 0.5
      end

      baggage = Sentry::Baggage.new({ "sample_rate" => "0.75" })

      parent_transaction = Sentry::Transaction.new(
        hub: Sentry.get_current_hub,
        baggage: baggage,
        sample_rand: 0.6
      )

      Sentry.start_transaction(transaction: parent_transaction)

      expect(sampling_contexts.last[:parent_sample_rate]).to eq(0.75)
      expect(parent_transaction.sampled).to be true

      transaction_baggage = parent_transaction.get_baggage

      expect(transaction_baggage.items["sample_rand"]).to eq("0.600000")
    end

    it "handles invalid sample_rand in baggage" do
      sentry_trace = "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1"
      baggage_header = "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=1.5"

      transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, baggage: baggage_header)

      expect(transaction).not_to be_nil

      expected_sample_rand = Sentry::Utils::SampleRand.generate_from_trace_id("771a43a4192642f0b136d5159a501700")

      expect(expected_sample_rand).to be >= 0.0
      expect(expected_sample_rand).to be < 1.0

      baggage = transaction.get_baggage

      expect(baggage.items).to eq({
        "trace_id" => "771a43a4192642f0b136d5159a501700",
        "sample_rand" => "1.5"
      })
    end
  end
end
