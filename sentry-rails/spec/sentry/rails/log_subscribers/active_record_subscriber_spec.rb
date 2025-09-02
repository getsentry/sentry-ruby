# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::LogSubscribers::ActiveRecordSubscriber do
  context "when logging is enabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = true

        config.rails.structured_logging.enabled = true
        config.rails.structured_logging.subscribers = { active_record: Sentry::Rails::LogSubscribers::ActiveRecordSubscriber }
      end
    end
    describe "integration with ActiveSupport::Notifications" do
      it "logs SQL events when database queries are executed" do
        Post.create!

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body]&.include?("Database query") && log[:attributes][:sql][:value]&.include?("INSERT") }
        expect(log_event).not_to be_nil
        expect(log_event[:level]).to eq("info")
        expect(log_event[:attributes][:sql][:value]).to include("INSERT INTO")
        expect(log_event[:attributes][:duration_ms][:value]).to be > 0
      end

      it "logs SELECT queries with proper attributes" do
        post = Post.create!

        Sentry.get_current_client.flush
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        Post.find(post.id)

        Sentry.get_current_client.flush

        log_event = sentry_logs.find { |log| log[:body]&.include?("Database query") }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:sql][:value]).to include("SELECT")
        expect(log_event[:attributes][:sql][:value]).to include("posts")
      end

      if Rails.version.to_f > 5.1
        it "excludes SCHEMA events" do
          ActiveSupport::Notifications.instrument("sql.active_record",
            sql: "CREATE TABLE temp_test_table (id INTEGER)",
            name: "SCHEMA",
            connection: ActiveRecord::Base.connection
          )

          Sentry.get_current_client.flush

          schema_logs = sentry_logs.select { |log| log[:attributes]&.dig(:sql, :value)&.include?("CREATE TABLE") }
          expect(schema_logs).to be_empty
        end
      end
    end

    if Rails.version.to_f >= 7.2
      describe "database configuration extraction" do
        it "includes database configuration in log attributes" do
          Post.create!

          Sentry.get_current_client.flush

          log_event = sentry_logs.find do |log|
            log[:body]&.include?("Database query") &&
              log[:attributes]&.dig(:sql, :value)&.include?("INSERT")
          end

          expect(log_event).not_to be_nil

          attributes = log_event[:attributes]
          expect(attributes[:db_system][:value]).to eq("sqlite3")
          expect(attributes[:db_name][:value]).to eq("db")
        end
      end
    end

    describe "statement name handling" do
      it "includes statement name in log message when available" do
        post = Post.create!
        Post.find(post.id)

        Sentry.get_current_client.flush

        log_event = sentry_logs.find do |log|
          log[:body]&.include?("Database query") &&
            log[:attributes]&.dig(:sql, :value)&.include?("SELECT") &&
            log[:attributes]&.dig(:statement_name, :value)&.include?("Load")
        end
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:statement_name][:value]).to include("Load")
      end

      it "handles queries without specific statement names" do
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        ActiveRecord::Base.connection.execute("SELECT 1")

        Sentry.get_current_client.flush

        log_event = sentry_logs.find do |log|
          log[:body] == "Database query" &&
            log[:attributes]&.dig(:sql, :value) == "SELECT 1"
        end
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:sql][:value]).to include("SELECT 1")
      end
    end

    describe "caching information" do
      it "includes cached flag when query is cached", skip: Rails.version.to_f < 5.1 ? "Rails 5.0.0 doesn't include cached flag in sql.active_record events" : false do
        ActiveRecord::Base.cache do
          post = Post.create!
          sentry_transport.events.clear
          sentry_transport.envelopes.clear

          Post.find(post.id)
          Post.find(post.id)

          Sentry.get_current_client.flush

          cached_log = sentry_logs.find { |log| log[:attributes]&.dig(:cached, :value) == true }
          expect(cached_log).not_to be_nil
        end
      end
    end
  end

  context "when logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = false

        config.rails.structured_logging.enabled = true
        config.rails.structured_logging.subscribers = { active_record: Sentry::Rails::LogSubscribers::ActiveRecordSubscriber }
      end
    end

    it "does not log events when logging is disabled" do
      initial_log_count = sentry_logs.count

      Post.create!

      Sentry.get_current_client.flush

      expect(sentry_logs.count).to eq(initial_log_count)
    end
  end

  include_examples "parameter filtering", described_class
end
