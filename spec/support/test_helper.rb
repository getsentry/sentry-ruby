# frozen_string_literal: true

require 'net/http'
require 'uri'

module Test
  module Helper
    module_function

    def rails_app_url
      ENV.fetch("SENTRY_E2E_RAILS_APP_URL")
    end

    def make_request(path)
      Net::HTTP.get_response(URI("#{rails_app_url}#{path}"))
    end

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

    def clear_logged_events
      Sentry.get_current_client.transport.clear
    end

    def logged_envelopes
      Sentry.get_current_client.transport.logged_envelopes
    end

    def logged_structured_events
      Sentry.logger.logged_events
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

    def debug_log_path
      @log_path ||= begin
        path = Pathname(__dir__).join("../../log")
        FileUtils.mkdir_p(path) unless path.exist?
        path.realpath
      end
    end

    def clear_logs
      Sentry.get_current_client.transport.clear
      Sentry.logger.clear
    end
  end
end
