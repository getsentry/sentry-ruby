# frozen_string_literal: true

RSpec.describe "Tracing", type: :e2e do
  def expect_valid_sample_rand(sample_rand)
    expect(sample_rand).not_to be_nil
    expect(sample_rand).to match(/^\d+\.\d+$/)
    sample_rand_value = sample_rand.to_f
    expect(sample_rand_value).to be >= 0.0
    expect(sample_rand_value).to be < 1.0
  end

  def expect_dsc_in_envelope_headers
    envelopes_with_dsc = logged_events[:envelopes].select do |envelope|
      envelope["headers"] && envelope["headers"]["trace"]
    end

    expect(envelopes_with_dsc).not_to be_empty

    dsc_metadata = envelopes_with_dsc.map { |envelope| envelope["headers"]["trace"] }

    envelopes_with_sample_rand = dsc_metadata.select { |dsc| dsc["sample_rand"] }
    expect(envelopes_with_sample_rand).not_to be_empty

    envelopes_with_sample_rand.each do |dsc|
      expect_valid_sample_rand(dsc["sample_rand"])
    end

    dsc_metadata
  end

  def get_http_server_transactions_with_headers
    transaction_events = logged_events[:events].select { |event| event["type"] == "transaction" }
    expect(transaction_events).not_to be_empty

    http_server_transactions = transaction_events.select { |event|
      event.dig("contexts", "trace", "op") == "http.server"
    }
    expect(http_server_transactions).not_to be_empty

    transactions_with_headers = http_server_transactions.select { |transaction|
      headers = transaction.dig("request", "headers")
      headers && (headers["Sentry-Trace"] || headers["sentry-trace"])
    }
    expect(transactions_with_headers).not_to be_empty

    transactions_with_headers
  end

  it "validates basic tracing functionality" do
    visit "/error"

    expect(page).to have_content("Svelte Mini App")
    expect(page).to have_button("Trigger Error")

    click_button "trigger-error-btn"

    expect(page).to have_content("Error:")

    expect(logged_events[:event_count]).to be > 0

    error_events = logged_events[:events].select { |event| event["exception"] }
    expect(error_events).not_to be_empty

    error_event = error_events.last
    exception_values = error_event.dig("exception", "values")
    expect(exception_values).not_to be_empty
    expect(exception_values.first["type"]).to eq("ZeroDivisionError")

    expect(error_event.dig("contexts", "trace")).not_to be_nil
    error_trace_id = error_event.dig("contexts", "trace", "trace_id")
    expect(error_trace_id).not_to be_nil

    transaction_events = logged_events[:events].select { |event| event["type"] == "transaction" }
    expect(transaction_events).not_to be_empty

    transactions_with_dsc = transaction_events.select { |event|
      event.dig("_meta", "dsc", "sample_rand")
    }

    transactions_with_dsc.each do |transaction|
      expect_valid_sample_rand(transaction.dig("_meta", "dsc", "sample_rand"))
    end
  end

  describe "propagated sample_rand behavior" do
    it "validates DSC metadata is properly generated and included in envelope headers" do
      visit "/error"

      expect(page).to have_content("Svelte Mini App")
      expect(page).to have_button("Trigger Error")

      click_button "trigger-error-btn"

      expect(page).to have_content("Error:")

      dsc_envelopes = expect_dsc_in_envelope_headers

      dsc_envelopes.each do |dsc|
        expect(dsc["trace_id"]).not_to be_nil
        expect(dsc["trace_id"]).to match(/^[a-f0-9]{32}$/)

        expect(dsc["sample_rate"]).not_to be_nil
        expect(dsc["sample_rate"].to_f).to be > 0.0

        expect(dsc["sample_rand"]).not_to be_nil
        expect_valid_sample_rand(dsc["sample_rand"])

        expect(dsc["sampled"]).to eq("true")
        expect(dsc["environment"]).to eql("production")
        expect(dsc["public_key"]).to eql("user")
      end

      transactions_with_headers = get_http_server_transactions_with_headers

      transactions_with_headers.each do |transaction|
        headers = transaction.dig("request", "headers")

        expect(headers).not_to be_nil

        sentry_trace = headers["Sentry-Trace"] || headers["sentry-trace"]
        expect(sentry_trace).not_to be_nil
        expect(sentry_trace).to match(/^[a-f0-9]{32}-[a-f0-9]{16}(-[01])?$/)

        baggage = headers["Baggage"] || headers["baggage"]
        expect(baggage).not_to be_nil
        expect(baggage).to include("sentry-sample_rand=")

        sample_rand_match = baggage.match(/sentry-sample_rand=([0-9.]+)/)
        expect(sample_rand_match).not_to be_nil
        sample_rand_value = sample_rand_match[1]
        expect_valid_sample_rand(sample_rand_value)

        trace_context = transaction.dig("contexts", "trace")
        expect(trace_context).not_to be_nil
        expect(trace_context["trace_id"]).to match(/^[a-f0-9]{32}$/)
        expect(trace_context["span_id"]).to match(/^[a-f0-9]{16}$/)
        expect(trace_context["op"]).to eq("http.server")
      end
    end

    it "validates DSC sample_rand generation across multiple requests" do
      visit "/error"

      expect(page).to have_content("Svelte Mini App")

      3.times do |i|
        click_button "trigger-error-btn"
        sleep 0.1
      end

      expect(page).to have_content("Error:")

      dsc_envelopes = expect_dsc_in_envelope_headers
      expect(dsc_envelopes.length).to be >= 3

      trace_ids = dsc_envelopes.map { |dsc| dsc["trace_id"] }.uniq
      sample_rands = dsc_envelopes.map { |dsc| dsc["sample_rand"] }.uniq

      expect(trace_ids.length).to be(1)
      expect(sample_rands.length).to be(1)

      sample_rands.each do |sample_rand|
        expect_valid_sample_rand(sample_rand)
      end

      transactions_with_headers = get_http_server_transactions_with_headers

      expect(transactions_with_headers.length).to eql(3)

      transactions_with_headers.each do |transaction|
        headers = transaction.dig("request", "headers")
        expect(headers).not_to be_nil

        sentry_trace = headers["Sentry-Trace"] || headers["sentry-trace"]
        expect(sentry_trace).not_to be_nil
        expect(sentry_trace).to match(/^[a-f0-9]{32}-[a-f0-9]{16}(-[01])?$/)

        baggage = headers["Baggage"] || headers["baggage"]
        expect(baggage).not_to be_nil
        expect(baggage).to include("sentry-sample_rand=")

        sample_rand_match = baggage.match(/sentry-sample_rand=([0-9.]+)/)
        expect(sample_rand_match).not_to be_nil
        sample_rand_value = sample_rand_match[1]
        expect_valid_sample_rand(sample_rand_value)

        trace_context = transaction.dig("contexts", "trace")
        expect(trace_context).not_to be_nil
        expect(trace_context["trace_id"]).to match(/^[a-f0-9]{32}$/)
        expect(trace_context["span_id"]).to match(/^[a-f0-9]{16}$/)
        expect(trace_context["op"]).to eq("http.server")
      end

      transaction_trace_ids = transactions_with_headers.map { |t| t.dig("contexts", "trace", "trace_id") }.uniq
      expect(transaction_trace_ids.length).to be(1)

      transaction_sample_rands = transactions_with_headers.map do |transaction|
        headers = transaction.dig("request", "headers")
        baggage = headers["Baggage"] || headers["baggage"]
        sample_rand_match = baggage.match(/sentry-sample_rand=([0-9.]+)/)
        sample_rand_match[1] if sample_rand_match
      end.compact.uniq

      expect(transaction_sample_rands.length).to be(1)
    end
  end
end
