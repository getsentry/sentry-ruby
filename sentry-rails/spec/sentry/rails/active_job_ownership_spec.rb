# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sentry::Rails.active_job_owns_adapter?" do
  let(:adapter_class_name) { "ActiveJob::QueueAdapters::SidekiqAdapter" }

  it "is true when Sentry is initialized and the adapter is not skipped" do
    make_basic_app

    expect(Sentry::Rails.active_job_owns_adapter?(adapter_class_name)).to be(true)
  end

  it "is false when the adapter is in skippable_job_adapters" do
    make_basic_app do |config|
      config.rails.skippable_job_adapters = [adapter_class_name]
    end

    expect(Sentry::Rails.active_job_owns_adapter?(adapter_class_name)).to be(false)
  end

  it "is false when Sentry is not initialized" do
    expect(Sentry::Rails.active_job_owns_adapter?(adapter_class_name)).to be(false)
  end
end
