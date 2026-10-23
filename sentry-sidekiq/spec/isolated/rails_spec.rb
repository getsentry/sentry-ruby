# frozen_string_literal: true

require_relative "support/rails_app"

RSpec.describe Sentry::Sidekiq do
  before do
    make_basic_app
  end

  it "adds sidekiq adapter to config.rails.skippable_job_adapters" do
    expect(Sentry.configuration.rails.skippable_job_adapters).to include("ActiveJob::QueueAdapters::SidekiqAdapter")
  end
end
