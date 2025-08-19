# frozen_string_literal: true

module Test
  module Helper
    module_function

    def logged_events
      @logged_events ||= begin
        extracted_events = []
        envelopes = []

        logged_envelopes.each do |event_data|
          envelopes << {
            "headers" => event_data["envelope_headers"],
            "items" => event_data["items"]
          }

          event_data["items"].each do |item|
            if ["event", "transaction"].include?(item["headers"]["type"])
              extracted_events << item["payload"]
            end
          end
        end

        {
          events: extracted_events,
          envelopes: envelopes,
          event_count: extracted_events.length,
          envelope_count: envelopes.length
        }
      end
    end

    def logged_envelopes
      Sentry.get_current_client.transport.logged_envelopes
    end

    # TODO: move this to a shared helper for all gems
    def perform_basic_setup
      Sentry.init do |config|
        config.sdk_logger = Logger.new(nil)
        config.dsn = Sentry::TestHelper::DUMMY_DSN
        config.transport.transport_class = Sentry::DummyTransport
        # so the events will be sent synchronously for testing
        config.background_worker_threads = 0
        yield(config) if block_given?
      end
    end
  end
end
