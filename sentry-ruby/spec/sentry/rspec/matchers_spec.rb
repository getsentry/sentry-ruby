# frozen_string_literal: true

require "spec_helper"
require "sentry/rspec"

RSpec.describe "Sentry RSpec Matchers" do
  include Sentry::TestHelper

  before do
    # simulate normal user setup
    Sentry.init do |config|
      config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
      config.enabled_environments = ["production"]
      config.environment = :test
    end

    setup_sentry_test
  end

  after do
    teardown_sentry_test
  end

  let(:exception) { StandardError.new("Gaah!") }

  describe "include_sentry_event" do
    it "matches events with the given message" do
      Sentry.capture_message("Ooops")

      expect(sentry_events).to include_sentry_event("Ooops")
    end

    it "does not match events with a different message" do
      Sentry.capture_message("Ooops")

      expect(sentry_events).not_to include_sentry_event("Different message")
    end

    it "matches events with exception" do
      Sentry.capture_exception(exception)

      expect(sentry_events).to include_sentry_event(exception: exception.class, message: exception.message)
    end

    it "does not match events with different exception" do
      exception = StandardError.new("Gaah!")

      Sentry.capture_exception(exception)

      expect(sentry_events).not_to include_sentry_event(exception: StandardError, message: "Oops!")
    end

    it "matches events with context" do
      Sentry.set_context("rails.error", { some: "stuff" })
      Sentry.capture_message("Ooops")

      expect(sentry_events).to include_sentry_event("Ooops")
        .with_context("rails.error" => { some: "stuff" })
    end

    it "does not match events with different context" do
      Sentry.set_context("rails.error", { some: "stuff" })
      Sentry.capture_message("Ooops")

      expect(sentry_events).not_to include_sentry_event("Ooops")
        .with_context("rails.error" => { other: "data" })
    end

    it "matches events with tags" do
      Sentry.set_tags(foo: "bar", baz: "qux")
      Sentry.capture_message("Ooops")

      expect(sentry_events).to include_sentry_event("Ooops")
        .with_tags({ foo: "bar", baz: "qux" })
    end

    it "does not match events with missing tags" do
      Sentry.set_tags(foo: "bar")
      Sentry.capture_message("Ooops")

      expect(sentry_events).not_to include_sentry_event("Ooops")
        .with_tags({ foo: "bar", baz: "qux" })
    end

    it "matches error events with tags and context" do
      Sentry.set_tags(foo: "bar", baz: "qux")
      Sentry.set_context("rails.error", { some: "stuff" })

      Sentry.capture_exception(exception)

      expect(sentry_events).to include_sentry_event(exception: exception.class, message: exception.message)
        .with_tags({ foo: "bar", baz: "qux" })
        .with_context("rails.error" => { some: "stuff" })
    end

    it "matches error events with tags and context provided as arguments" do
      Sentry.set_tags(foo: "bar", baz: "qux")
      Sentry.set_context("rails.error", { some: "stuff" })

      Sentry.capture_exception(exception)

      expect(sentry_events).to include_sentry_event(
        exception: exception.class,
        message: exception.message,
        tags: { foo: "bar", baz: "qux" },
        context: { "rails.error" => { some: "stuff" } }
      )
    end

    it "produces a useful failure message" do
      Sentry.capture_message("Actual message")

      expect {
        expect(sentry_events).to include_sentry_event("Expected message")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Failed to find event matching:")
        expect(error.message).to include("message: \"Expected message\"")
        expect(error.message).to include("Captured events:")
        expect(error.message).to include("\"message\": \"Actual message\"")
      end
    end
  end
end
