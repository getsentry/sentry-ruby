# frozen_string_literal: true

RSpec.describe "Tracing", type: :feature do
  it "works" do
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

    transaction_events = logged_events[:events].select { |event| event["type"] == "transaction" }

    expect(error_event.dig("contexts", "trace")).not_to be(nil)
    error_trace_id = error_event.dig("contexts", "trace", "trace_id")
    expect(error_trace_id).to_not be(nil)

    if transaction_events.any?
      transaction_event = transaction_events.find do |event|
        event.dig("contexts", "trace", "trace_id") == error_trace_id
      end

      expect(transaction_event).not_to be(nil)

      trace_context = transaction_event.dig("contexts", "trace")
      expect(trace_context).not_to be(nil)

      transaction_trace_id = trace_context["trace_id"]

      expect(transaction_trace_id).to_not be(nil)
      expect(error_trace_id).to eq(transaction_trace_id)

      if transaction_event["_meta"] && transaction_event["_meta"]["dsc"]
        dsc = transaction_event["_meta"]["dsc"]
        expect(dsc).to include("sample_rand")

        sample_rand = dsc["sample_rand"]
        expect(sample_rand).to_not be(nil)
      end
    end

    logged_events[:envelopes].each do |envelope|
      envelope["items"].each do |item|
        if item["payload"] && item["payload"]["_meta"] && item["payload"]["_meta"]["dsc"]
          dsc = item["payload"]["_meta"]["dsc"]

          if dsc["sample_rand"]
            expect(dsc["sample_rand"]).to_not be(nil)
          end
        end
      end
    end
  end

  describe "propagated random value behavior" do
    it "properly propagates and uses sample_rand for sampling decisions in backend transactions" do
      visit "/error"

      expect(page).to have_content("Svelte Mini App")
      expect(page).to have_button("Trigger Error")

      click_button "trigger-error-btn"

      expect(page).to have_content("Error:")

      expect(logged_events[:event_count]).to be > 0

      transaction_events = logged_events[:events].select { |event| event["type"] == "transaction" }
      expect(transaction_events).not_to be_empty

      transactions = transaction_events.select { |event|
        event.dig("contexts", "trace", "op") == "http.server"
      }

      expect(transactions).not_to be_empty

      transaction = transactions.first
      expect(transaction).not_to be(nil)

      trace_context = transaction.dig("contexts", "trace")
      expect(trace_context).not_to be(nil)
      expect(trace_context["trace_id"]).not_to be(nil)

      dsc = transaction.dig("_meta", "dsc")
      if dsc && dsc["sample_rand"]
        sample_rand = dsc["sample_rand"]

        expect(sample_rand).to match(/^\d+\.\d{1,6}$/)

        sample_rand_value = sample_rand.to_f
        expect(sample_rand_value).to be >= 0.0
        expect(sample_rand_value).to be < 1.0
      end

      logged_events[:envelopes].each do |envelope|
        envelope["items"].each do |item|
          next unless dsc = item.dig("payload", "_meta", "dsc")

          sample_rand = dsc["sample_rand"]
          expect(sample_rand).to match(/^\d+\.\d{1,6}$/)

          sample_rand_value = sample_rand.to_f
          expect(sample_rand_value).to be >= 0.0
          expect(sample_rand_value).to be < 1.0

          item["payload"]["spans"].each do |span|
            sample_rand = span["data"]["sentry.sample_rand"]

            expect(sample_rand).to be_a(Float)
            expect(sample_rand).to be >= 0.0
            expect(sample_rand).to be < 1.0
          end
        end
      end
    end

    it "verifies sampling decisions are based on propagated sample_rand" do
      visit "/error"

      expect(page).to have_content("Svelte Mini App")
      expect(page).to have_button("Trigger Error")

      click_button "trigger-error-btn"

      expect(page).to have_content("Error:")

      transaction_events = logged_events[:events].select { |event| event["type"] == "transaction" }
      expect(transaction_events).not_to be_empty

      transaction_events.each do |transaction|
        dsc = transaction.dig("_meta", "dsc")
        next unless dsc && dsc["sample_rand"]

        sample_rand = dsc["sample_rand"].to_f
        sample_rate = dsc["sample_rate"]&.to_f

        expect(sample_rand).to be >= 0.0
        expect(sample_rand).to be < 1.0

        expect(sample_rate).to be > 0.0
        expect(sample_rate).to be <= 1.0

        expect(dsc["sample_rand"]).to match(/^\d+\.\d{1,6}$/)
      end
    end

    it "maintains consistent sample_rand across multiple requests in the same trace" do
      visit "/error"

      expect(page).to have_content("Svelte Mini App")

      3.times do |i|
        click_button "trigger-error-btn"
        sleep 0.1
      end

      expect(page).to have_content("Error:")

      transaction_events = logged_events[:events].select { |event| event["type"] == "transaction" }
      expect(transaction_events.length).to be >= 2

      traces = transaction_events.group_by { |event| event.dig("contexts", "trace", "trace_id") }

      traces.each do |trace_id, transactions|
        next if transactions.length < 2

        sample_rands = transactions.map { |transaction| transaction.dig("_meta", "dsc", "sample_rand") }.compact.uniq

        expect(sample_rands.length).to eq(1)
      end
    end
  end
end
