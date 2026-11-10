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

    def post_request(path, headers = {})
      Net::HTTP.post(URI("#{rails_app_url}#{path}"), "", headers)
    end

    BACKEND_JOB_REPORTING = {
      "sidekiq" => { origin: "auto.queue.sidekiq", op: "queue.process" },
      "resque" => { origin: "auto.queue.resque", op: "queue.resque" },
      "delayed_job" => { origin: "auto.queue.delayed_job", op: "queue.delayed_job" }
    }.freeze

    ACTIVE_JOB_REPORTING = { origin: "auto.queue.active_job", op: "queue.process" }.freeze

    def active_job_adapter
      ENV.fetch("SENTRY_E2E_ACTIVE_JOB_ADAPTER", "async")
    end

    def backend_gem
      ENV.fetch("SENTRY_E2E_BACKEND_GEM", "reporting")
    end

    def backend_gem_loaded?
      BACKEND_JOB_REPORTING.key?(active_job_adapter) && backend_gem != "not_installed"
    end

    def backend_reports_jobs?
      backend_gem_loaded? && backend_gem == "reporting"
    end

    def active_job_records_publish_span?
      !backend_reports_jobs? && !(backend_gem_loaded? && active_job_adapter == "sidekiq")
    end

    def jobs_continue_enqueuing_trace?
      backend_gem_loaded? && (backend_gem == "opted_out" || active_job_adapter == "sidekiq")
    end

    def runs_jobs_in_request?
      active_job_adapter == "inline"
    end

    def backend_retries_jobs?
      %w[sidekiq delayed_job].include?(active_job_adapter)
    end

    def job_executions_share_a_trace?
      !backend_reports_jobs? || active_job_adapter == "sidekiq"
    end

    def expected_job_origin
      backend_gem_loaded? ? BACKEND_JOB_REPORTING.fetch(active_job_adapter)[:origin] : ACTIVE_JOB_REPORTING[:origin]
    end

    def expected_job_op
      backend_reports_jobs? ? BACKEND_JOB_REPORTING.fetch(active_job_adapter)[:op] : ACTIVE_JOB_REPORTING[:op]
    end

    def logged_payloads(type)
      logged_envelopes.flat_map do |envelope|
        envelope["items"]
          .select { |item| item.dig("headers", "type") == type }
          .map { |item| item["payload"] }
      end
    end

    def job_transactions(job_class)
      logged_payloads("transaction").select do |transaction|
        transaction.dig("contexts", "trace", "origin") == expected_job_origin &&
          transaction["transaction"].to_s.split("/").last == job_class
      end
    end

    def wait_for(description, timeout: 15, settle: 0)
      deadline = Time.now + timeout
      found = nil
      settled_at = nil

      loop do
        current = yield
        if current && current == found
          return current if Time.now >= settled_at
        elsif current
          found = current
          settled_at = Time.now + settle
        end

        raise "timed out waiting for #{description}" if Time.now > deadline

        sleep 0.1
      end
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
