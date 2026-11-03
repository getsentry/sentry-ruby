# frozen_string_literal: true

require "spec_helper"
require "sentry/rails/error_subscriber"

RSpec.describe Sentry::Rails::CaptureExceptions do
  let(:transport) { Sentry.get_current_client.transport }

  before do
    make_basic_app
  end

  def wrapper_with_cause
    cause = RuntimeError.new("the cause")
    wrapper = begin
      begin
        raise cause
      rescue
        raise ArgumentError, "the wrapper"
      end
    rescue => e
      e
    end

    [wrapper, cause]
  end

  def run_middleware(exception)
    middleware = described_class.new(->(_env) { raise exception })
    expect { middleware.call(Rack::MockRequest.env_for("/")) }.to raise_error(exception)
  end

  it "doesn't let the error reporter send the cause of an exception it captured" do
    wrapper, cause = wrapper_with_cause

    run_middleware(wrapper)
    Sentry::Rails::ErrorSubscriber.new.report(cause, handled: false, severity: :error, context: {})

    expect(transport.events.count).to eq(1)
  end

  it "doesn't capture an exception whose cause was already reported by the error reporter" do
    wrapper, cause = wrapper_with_cause

    Sentry::Rails::ErrorSubscriber.new.report(cause, handled: false, severity: :error, context: {})
    run_middleware(wrapper)

    expect(transport.events.count).to eq(1)
  end

  it "doesn't mark the causes as captured when the wrapper is not reported" do
    wrapper, cause = wrapper_with_cause
    Sentry.configuration.excluded_exceptions += ["ArgumentError"]

    run_middleware(wrapper)
    Sentry::Rails::ErrorSubscriber.new.report(cause, handled: false, severity: :error, context: {})

    expect(transport.events.count).to eq(1)
  end

  it "still captures unrelated exceptions" do
    wrapper, _cause = wrapper_with_cause

    run_middleware(wrapper)
    run_middleware(RuntimeError.new("other"))

    expect(transport.events.count).to eq(2)
  end
end
