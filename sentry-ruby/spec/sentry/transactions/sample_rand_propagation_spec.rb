# frozen_string_literal: true

RSpec.describe "Transactions and sample rand propagation" do
  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
    end
  end

  describe "sample_rand propagation" do
    it "uses value from the baggage" do
      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
        "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=0.123456"
      }

      transaction = Sentry.continue_trace(env, name: "backend_request", op: "http.server")
      propagation_context = Sentry.get_current_scope.propagation_context

      expect(propagation_context.sample_rand).to eq(0.123456)
      expect(transaction.sample_rand).to eq(0.123456)

      expect(transaction.sample_rand).to eq(propagation_context.sample_rand)
    end

    it "generates deterministic value from trace id if there's no value in the baggage" do
      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
        "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700"
      }

      transaction = Sentry.continue_trace(env, name: "backend_request", op: "http.server")
      propagation_context = Sentry.get_current_scope.propagation_context

      expect(transaction.sample_rand).to eq(propagation_context.sample_rand)

      generator = Sentry::Utils::SampleRand.new(trace_id: "771a43a4192642f0b136d5159a501700")
      expected = generator.generate_from_trace_id

      expect(transaction.sample_rand).to eq(expected)
      expect(propagation_context.sample_rand).to eq(expected)
    end

    [
      { sample_rand: 0.1, sample_rate: 0.5, should_sample: true },
      { sample_rand: 0.7, sample_rate: 0.5, should_sample: false },
      { sample_rand: 0.5, sample_rate: 0.5, should_sample: false },
      { sample_rand: 0.499999, sample_rate: 0.5, should_sample: true }
  ].each do |test_case|
    it "with #{test_case.inspect} - properly handles sampling decisions" do
      Sentry.configuration.traces_sample_rate = test_case[:sample_rate]

      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-",
        "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=#{test_case[:sample_rand]}"
      }

      transaction = Sentry.continue_trace(env, name: "test")
      Sentry.start_transaction(transaction: transaction)

      expect(transaction.sampled).to eq(test_case[:should_sample])
    end
  end

    it "ensures baggage propagation includes correct sample_rand" do
      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
        "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=0.654321"
      }

      transaction = Sentry.continue_trace(env, name: "backend_request")
      baggage = transaction.get_baggage

      expect(baggage.items["sample_rand"]).to eq("0.654321")

      Sentry.get_current_scope.set_span(transaction)

      headers = Sentry.get_trace_propagation_headers

      expect(headers["baggage"]).to include("sentry-sample_rand=0.654321")
    end

    it "handles edge cases and invalid sample_rand values" do
      env = {
        "HTTP_SENTRY_TRACE" => "771a43a4192642f0b136d5159a501700-7c51afd529da4a2a-1",
        "HTTP_BAGGAGE" => "sentry-trace_id=771a43a4192642f0b136d5159a501700,sentry-sample_rand=1.5"
      }

      transaction = Sentry.continue_trace(env, name: "test")
      propagation_context = Sentry.get_current_scope.propagation_context

      generator = Sentry::Utils::SampleRand.new(trace_id: "771a43a4192642f0b136d5159a501700")
      expected = generator.generate_from_trace_id

      expect(transaction.sample_rand).to eq(expected)
      expect(propagation_context.sample_rand).to eq(expected)
    end

    it "works correctly with multiple sequential requests" do
      requests = [
        { sample_rand: 0.111111, trace_id: "11111111111111111111111111111111" },
        { sample_rand: 0.222222, trace_id: "22222222222222222222222222222222" },
        { sample_rand: 0.333333, trace_id: "33333333333333333333333333333333" }
      ]

      requests.each do |request|
        env = {
          "HTTP_SENTRY_TRACE" => "#{request[:trace_id]}-7c51afd529da4a2a-1",
          "HTTP_BAGGAGE" => "sentry-trace_id=#{request[:trace_id]},sentry-sample_rand=#{request[:sample_rand]}"
        }

        transaction = Sentry.continue_trace(env, name: "test")

        expect(transaction.sample_rand).to eq(request[:sample_rand])
        expect(transaction.trace_id).to eq(request[:trace_id])
      end
    end

    it "handles corrupted trace context during transaction creation" do
      # TODO: does it make sense to even handle such case?
      transaction = Sentry::Transaction.new(
        hub: Sentry.get_current_hub,
        trace_id: nil,
        name: "corrupted_trace_test",
        op: "test"
      )

      expect(transaction.sample_rand).to be_a(Float)
      expect(transaction.sample_rand).to be >= 0.0
      expect(transaction.sample_rand).to be < 1.0
      expect(Sentry::Utils::SampleRand.valid?(transaction.sample_rand)).to be true

      Sentry.start_transaction(transaction: transaction)
      expect([true, false]).to include(transaction.sampled)

      baggage = transaction.get_baggage
      expect(baggage.items["sample_rand"]).to match(/\A\d+\.\d{6}\z/)
    end
  end
end
