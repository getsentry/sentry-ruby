require "active_job"
require "spec_helper"

RSpec.describe "Sentry::SendEventJob" do
  before do
    make_basic_app
  end

  let(:event) do
    Sentry.get_current_client.event_from_message("test message")
  end
  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "reports events to Sentry" do
    Sentry::SendEventJob.perform_now(event)

    expect(transport.events.count).to eq(1)
    event = transport.events.first
    expect(event.message).to eq("test message")
  end

  it "reports events to Sentry" do
    Sentry.configuration.before_send = lambda do |event, hint|
      event.tags[:hint] = hint
      event
    end

    Sentry::SendEventJob.perform_now(event, { foo: "bar" })

    expect(transport.events.count).to eq(1)
    event = transport.events.first
    expect(event.message).to eq("test message")
    expect(event.tags[:hint][:foo]).to eq("bar")
  end
end
