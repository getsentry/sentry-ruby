# frozen_string_literal: true

RSpec.describe Sentry::StructuredLogger do
  context "when enable_logs is set to false" do
    before do
      perform_basic_setup do |config|
        config.enable_logs = false
      end
    end

    it "initializes" do
      expect(Sentry.logger).to be_a(described_class)
    end
  end

  context "when log events are enabled" do
    before do
      perform_basic_setup do |config|
        config.max_log_events = 1
        config.enable_logs = true
      end
    end

    ["info", "warn", "error", "fatal"].each do |level|
      describe "##{level}" do
        it "logs using default logger and LogEvent logger with extra attributes" do
          payload = { user_id: 123, action: "create" }

          Sentry.logger.public_send(level, "Hello World", payload)

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello World")
          expect(log_event[:attributes]).to include({ user_id: { value: 123, type: "integer" } })
          expect(log_event[:attributes]).to include({ action: { value: "create", type: "string" } })
        end

        it "logs with template parameters" do
          Sentry.logger.public_send(level, "Hello %s it is %s", ["Jane", "Monday"])

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane it is Monday")
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %s it is %s", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.0"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.1"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with template parameters and extra attributres" do
          Sentry.logger.public_send(level, "Hello %s it is %s", ["Jane", "Monday"], extra: 312)

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane it is Monday")
          expect(log_event[:attributes][:extra]).to eql({ value: 312, type: "integer" })
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %s it is %s", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.0"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.1"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with hash-based template parameters" do
          Sentry.logger.public_send(level, "Hello %{name}, it is %{day}", name: "Jane", day: "Monday")

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane, it is Monday")
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %{name}, it is %{day}", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.name"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.day"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with hash-based template parameters and extra attributes" do
          Sentry.logger.public_send(level, "Hello %{name}, it is %{day}", name: "Jane", day: "Monday", user_id: 123)

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane, it is Monday")
          expect(log_event[:attributes][:user_id]).to eql({ value: 123, type: "integer" })
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %{name}, it is %{day}", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.name"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameter.day"]).to eql({ value: "Monday", type: "string" })
        end

        it "doesn't choke on malformed UTF-8 strings" do
          malformed_string = "Hello World\x92".dup.force_encoding("UTF-8")
          Sentry.logger.public_send(level, malformed_string, user_id: 123)

          expect(sentry_logs).to be_empty
        end

        it "doesn't choke on malformed UTF-8 in attributes" do
          malformed_user_agent = "Mozilla/5.0 (compatible; Yahoo! Slurp; http://help.yahoo.com/help/us/ysearch/slurp\xA1\xB1)".dup.force_encoding("UTF-8")
          Sentry.logger.public_send(level, "Valid message", user_agent: malformed_user_agent)

          expect(sentry_logs).to be_empty
        end
      end
    end

    describe "using config.before_send_log" do
      let(:transport) do
        Sentry.get_current_client.transport
      end

      before do
        perform_basic_setup do |config|
          config.enable_logs = true
          config.send_client_reports = send_client_reports
          config.max_log_events = 1
          config.before_send_log = before_send_log
        end
      end

      context "when send_client_reports is turned off and the callback returns a log event" do
        let(:send_client_reports) { false }

        let(:before_send_log) do
          ->(log) {
            log.attributes["hello"] = "world"
            log
          }
        end

        it "sends processed log events" do
          Sentry.logger.info("Hello World", user_id: 125, action: "create")
          Sentry.logger.info("Hello World", user_id: 123, action: "create")
          Sentry.logger.info("Hello World", user_id: 127, action: "create")

          expect(sentry_logs.size).to be(3)

          log_event = sentry_logs.last

          expect(log_event[:attributes]["hello"]).to eql({ value: "world", type: "string" })
        end
      end

      context "when send_client_reports is turned on and the callback returns a log event" do
        let(:send_client_reports) { true }

        let(:before_send_log) do
          ->(log) {
          if log.attributes[:user_id] == 123
            log
          end
          }
        end

        it "records discarded events" do
          Sentry.logger.info("Hello World", user_id: 125, action: "create")
          Sentry.logger.info("Hello World", user_id: 123, action: "create")
          Sentry.logger.info("Hello World", user_id: 127, action: "create")

          expect(sentry_logs.size).to be(1)

          expect(transport.discarded_events).to include([:before_send, "log_item"] => 2)
        end
      end
    end
  end
end
