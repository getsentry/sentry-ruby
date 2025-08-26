# frozen_string_literal: true

require "spec_helper"
require "sentry/rails/log_subscribers/active_job_subscriber"

require_relative "../../support/test_jobs"

RSpec.describe Sentry::Rails::LogSubscribers::ActiveJobSubscriber, skip: Rails.version.to_f < 5.1 do
  before do
    make_basic_app do |config|
      config.enable_logs = true
      config.rails.structured_logging.enabled = true
      config.rails.structured_logging.subscribers = { active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber }
    end
  end

  describe "integration with ActiveSupport::Notifications" do
    it "logs job perform events when jobs are executed" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      NormalJob.perform_now

      Sentry.get_current_client.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job performed") && log[:body]&.include?("NormalJob") }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("info")
      expect(log_event[:attributes][:job_class][:value]).to eq("NormalJob")
      expect(log_event[:attributes][:duration_ms][:value]).to be > 0
    end

    it "logs job enqueue events when jobs are enqueued" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      NormalJob.perform_later

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job enqueued") && log[:body]&.include?("NormalJob") }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("info")
      expect(log_event[:attributes][:job_class][:value]).to eq("NormalJob")
      expect(log_event[:attributes][:job_id][:value]).to be_a(String)
      expect(log_event[:attributes][:queue_name][:value]).to eq("default")
    end
  end

  describe "job attributes extraction" do
    it "includes job attributes in log events" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      NormalJob.perform_now

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job performed") }
      expect(log_event).not_to be_nil

      attributes = log_event[:attributes]
      expect(attributes[:job_class][:value]).to eq("NormalJob")
      expect(attributes[:job_id][:value]).to be_a(String)
      expect(attributes[:queue_name][:value]).to eq("default")
      expect(attributes[:executions][:value]).to eq(1)
      expect(attributes[:priority][:value]).to be_a(Integer).or be_nil
    end

    it "includes adapter information when available" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      NormalJob.perform_now

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job performed") }
      expect(log_event).not_to be_nil

      attributes = log_event[:attributes]
      expect(attributes[:adapter][:value]).to include("TestAdapter")
    end
  end

  describe "scheduled job handling" do
    it "includes scheduling information for delayed jobs" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      # Simulate a scheduled job enqueue event
      job = NormalJob.new
      job.job_id = SecureRandom.uuid
      job.queue_name = "default"
      job.priority = nil
      job.scheduled_at = 1.hour.from_now

      ActiveSupport::Notifications.instrument("enqueue.active_job", job: job)

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job enqueued") }
      expect(log_event).not_to be_nil

      attributes = log_event[:attributes]
      expect(attributes[:scheduled_at][:value]).to be_a(String)
      expect(attributes[:delay_seconds][:value]).to be > 0
    end
  end

  describe "argument filtering" do
    context "when send_default_pii is enabled" do
      before do
        make_basic_app do |config|
          config.enable_logs = true
          config.send_default_pii = true
          config.rails.structured_logging.enabled = true
          config.rails.structured_logging.subscribers = { active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber }
        end
      end

      it "includes filtered job arguments" do
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        # Create a job class that doesn't raise an error
        test_job_class = Class.new(ActiveJob::Base) do
          def self.name
            "TestJobWithArgs"
          end

          def perform(*args, **kwargs)
            # Job implementation that doesn't raise
          end
        end

        test_job_class.perform_now("safe_arg", integer: 42, post: Post.create!)

        Sentry.get_current_client.flush

        log_event = sentry_logs.find { |log| log[:body]&.include?("Job performed") }
        expect(log_event).not_to be_nil

        attributes = log_event[:attributes]
        expect(attributes[:arguments][:value]).to be_a(Array)
        expect(attributes[:arguments][:value]).to include("safe_arg")
      end

      it "filters sensitive arguments" do
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        original_filter_params = Rails.application.config.filter_parameters.dup
        Rails.application.config.filter_parameters += [:token]

        # Create a job class that accepts sensitive arguments
        test_job_class = Class.new(ActiveJob::Base) do
          def self.name
            "TestJobWithSensitiveArgs"
          end

          def perform(password:, token:, safe_data:)
            # Job implementation
          end
        end

        test_job_class.perform_now(password: "secret123", token: "abc123", safe_data: "public")

        Sentry.get_current_client.flush

        log_event = sentry_logs.find { |log| log[:body]&.include?("Job performed") }
        expect(log_event).not_to be_nil

        attributes = log_event[:attributes]
        arguments = attributes[:arguments][:value]

        expect(arguments.first).to include(safe_data: "public")
        expect(arguments.first).to include(password: "[FILTERED]")
        expect(arguments.first).to include(token: "[FILTERED]")

        Rails.application.config.filter_parameters = original_filter_params
      end
    end

    context "when send_default_pii is disabled" do
      it "does not include job arguments" do
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        # Create a job class that doesn't raise an error
        test_job_class = Class.new(ActiveJob::Base) do
          def self.name
            "TestJobNoArgs"
          end

          def perform(*args, **kwargs)
            # Job implementation that doesn't raise
          end
        end

        test_job_class.perform_now("arg", integer: 42, post: Post.create!)

        Sentry.get_current_client.flush

        log_event = sentry_logs.find { |log| log[:body]&.include?("Job performed") }
        expect(log_event).not_to be_nil

        attributes = log_event[:attributes]
        expect(attributes).not_to have_key(:arguments)
      end
    end
  end

  describe "retry and error handling" do
    it "logs retry_stopped events" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      # Simulate a retry_stopped event
      job = FailedJob.new
      error = StandardError.new("Test error")

      ActiveSupport::Notifications.instrument("retry_stopped.active_job",
        job: job,
        error: error
      )

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job retry stopped") }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("error")
      expect(log_event[:attributes][:job_class][:value]).to eq("FailedJob")
      expect(log_event[:attributes][:error_class][:value]).to eq("StandardError")
      expect(log_event[:attributes][:error_message][:value]).to eq("Test error")
    end

    it "logs discard events" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      # Simulate a discard event
      job = FailedJob.new
      error = StandardError.new("Test error")

      ActiveSupport::Notifications.instrument("discard.active_job",
        job: job,
        error: error
      )

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job discarded") }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("warn")
      expect(log_event[:attributes][:job_class][:value]).to eq("FailedJob")
      expect(log_event[:attributes][:error_class][:value]).to eq("StandardError")
      expect(log_event[:attributes][:error_message][:value]).to eq("Test error")
    end

    it "logs discard events without error" do
      sentry_transport.events.clear
      sentry_transport.envelopes.clear

      # Simulate a discard event without error
      job = FailedJob.new

      ActiveSupport::Notifications.instrument("discard.active_job",
        job: job,
        error: nil
      )

      Sentry.get_current_client.flush

      log_event = sentry_logs.find { |log| log[:body]&.include?("Job discarded") }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("warn")
      expect(log_event[:attributes][:job_class][:value]).to eq("FailedJob")
      expect(log_event[:attributes]).not_to have_key(:error_class)
      expect(log_event[:attributes]).not_to have_key(:error_message)
    end
  end

  describe "when logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = false
        config.rails.structured_logging.enabled = true
        config.rails.structured_logging.subscribers = { active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber }
      end
    end

    it "does not log events when logging is disabled" do
      initial_log_count = sentry_logs.count

      NormalJob.perform_now

      if Sentry.get_current_client&.log_event_buffer
        Sentry.get_current_client.flush
      end

      expect(sentry_logs.count).to eq(initial_log_count)
    end
  end

  # Test ParameterFilter functionality using shared examples
  include_examples "parameter filtering", described_class
end
