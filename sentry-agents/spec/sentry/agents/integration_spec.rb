# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Agents do
  it "registers the integration" do
    expect(Sentry.integrations["agents"]).to eq(
      name: "sentry.ruby.agents",
      version: Sentry::Agents::VERSION
    )
  end
end
