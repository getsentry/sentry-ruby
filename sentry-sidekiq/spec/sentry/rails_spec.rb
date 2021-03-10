return unless ENV["WITH_SENTRY_RAILS"]

require "rails"
require "sentry-rails"
require "spec_helper"

class TestApp < Rails::Application
end

def make_basic_app
  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.hosts = nil
  app.config.secret_key_base = "test"
  app.config.eager_load = true
  app.initializer :configure_sentry do
    Sentry.init do |config|
      config.release = 'beta'
      config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
      config.transport.transport_class = Sentry::DummyTransport
      # for sending events synchronously
      config.background_worker_threads = 0
      yield(config, app) if block_given?
    end
  end

  app.initialize!
  Rails.application = app
  app
end

RSpec.describe Sentry::Sidekiq do
  before do
    make_basic_app
  end

  it "adds sidekiq adapter to config.rails.skippable_job_adapters" do
    expect(Sentry.configuration.rails.skippable_job_adapters).to include("ActiveJob::QueueAdapters::SidekiqAdapter")
  end
end
