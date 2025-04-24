# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Logger do
  context "when log events are not enabled" do
    subject(:logger) { Sentry::Logger.new(output)}

    let(:output) { StringIO.new }

    def expect_log(level, message)
      yield(message)
      expect(output.string).to include(level.upcase)
      expect(output.string).to include(message)
    end

    before do
      perform_basic_setup do |config|
        config.logger = Sentry::Logger.new(output)
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
end
