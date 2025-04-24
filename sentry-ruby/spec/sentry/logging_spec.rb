# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Logging do
  let(:default_logger) { Sentry::Logger.new(output)}
  let(:output) { StringIO.new }

  def expect_log(level, message)
    yield(message)
    expect(output.string).to include(level.upcase)
    expect(output.string).to include(message)
  end

  context "when log events are not enabled" do

    before do
      perform_basic_setup do |config|
        config.logger = default_logger
      end
    end

    # TODO: At the moment the Sentry::Logger enforces info - is that intentional?
    ["info", "warn", "error", "fatal"].each do |level|
      describe "##{level}" do
        it "logs using configured default logger" do
          expect_log(level, "Hello World") { |msg| Sentry.logger.public_send(level, msg) }
        end
      end
    end
  end

  context "when log events are enabled" do
    before do
      perform_basic_setup do |config|
        config.logger = default_logger
        config._experiments = { enable_logs: true }
      end
    end

    describe "#info" do
      it "logs using default logger and LogEvent logger" do
        expect_log("info", "Hello World") { |msg| Sentry.logger.info(msg) }

        expect(sentry_events.size).to be(1)
      end
    end
  end
end
