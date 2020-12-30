require "spec_helper"
require "sentry/integrable"

RSpec.describe Sentry::Integrable do
  module Sentry
    module FakeIntegration
      extend Sentry::Integrable

      register_integration name: "fake_integration", version: "0.1.0"
    end
  end

  it "registers correct meta" do
    meta = Sentry.integrations["fake_integration"]

    expect(meta).to eq({ name: "sentry.ruby.fake_integration", version: "0.1.0" })
  end

  describe "helpers generation" do
    before do
      perform_basic_setup
    end

    let(:exception) { ZeroDivisionError.new("1/0") }
    let(:message) { "test message" }

    it "generates Sentry::FakeIntegration.capture_exception" do
      hint = nil

      Sentry.configuration.before_send = lambda do |event, h|
        hint = h
        event
      end

      Sentry::FakeIntegration.capture_exception(exception, hint: { additional_hint: "foo" })

      expect(hint).to eq({ additional_hint: "foo", integration: "fake_integration", exception: exception })
    end

    it "generates Sentry::FakeIntegration.capture_exception" do
      hint = nil

      Sentry.configuration.before_send = lambda do |event, h|
        hint = h
        event
      end

      Sentry::FakeIntegration.capture_message(message, hint: { additional_hint: "foo" })

      expect(hint).to eq({ additional_hint: "foo", integration: "fake_integration", message: message })
    end

    it "sets correct meta when the event is captured by integration helpers" do
      event = Sentry::FakeIntegration.capture_message(message)
      expect(event.sdk).to eq({ name: "sentry.ruby.fake_integration", version: "0.1.0" })
    end

    it "doesn't change the events captured by original helpers" do
      event = Sentry.capture_message(message)
      expect(event.sdk).to eq(Sentry.sdk_meta)
    end
  end
end
