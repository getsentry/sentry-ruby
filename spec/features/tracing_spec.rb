# frozen_string_literal: true

RSpec.describe "Tracing", type: :feature do
  it "works", js: false do
    visit "/error"

    expect(page).to have_content("Svelte Mini App")
    expect(page).to have_button("Trigger Error")
    click_button "trigger-error-btn"
    expect(page).to have_content("Error:")

    events_data = get_rails_events

    expect(events_data["event_count"]).to be > 0

    error_events = events_data["events"].select { |event| event["exception"] }
    expect(error_events).not_to be_empty

    error_event = error_events.first
    exception_values = error_event.dig("exception", "values")
    expect(exception_values).not_to be_empty
    expect(exception_values.first["type"]).to eq("ZeroDivisionError")

    transaction_events = events_data["events"].select { |event| event["type"] == "transaction" }

    expect(error_event.dig("contexts", "trace")).not_to be_nil
    error_trace_id = error_event.dig("contexts", "trace", "trace_id")
    expect(error_trace_id).to_not be(nil)

    if transaction_events.any?
      transaction_event = transaction_events.first
      trace_context = transaction_event.dig("contexts", "trace")

      expect(trace_context).not_to be_nil

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

    events_data["envelopes"].each do |envelope|
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

  private

  def get_rails_events
    log_file_path = File.join(Dir.pwd, "log", "sentry_debug_events.log")

    return { "events" => [], "envelopes" => [], "event_count" => 0, "envelope_count" => 0 } unless File.exist?(log_file_path)

    events = []
    File.readlines(log_file_path).each do |line|
      line = line.strip
      next if line.empty?

      begin
        events << JSON.parse(line)
      rescue JSON::ParserError => e
        puts "Failed to parse line: #{line}, error: #{e.message}"
      end
    end

    extracted_events = []
    envelopes = []

    events.each do |event_data|
      envelopes << {
        "headers" => event_data["envelope_headers"],
        "items" => event_data["items"]
      }

      # Extract actual events from envelope items
      event_data["items"].each do |item|
        if item["headers"]["type"] == "event"
          extracted_events << item["payload"]
        end
      end
    end

    {
      "events" => extracted_events,
      "envelopes" => envelopes,
      "event_count" => extracted_events.length,
      "envelope_count" => envelopes.length,
      "raw_events" => events
    }
  end

  def clear_rails_events
    log_file_path = File.join(Dir.pwd, "log", "sentry_debug_events.log")
    File.write(log_file_path, "") if File.exist?(log_file_path)
  end
end
