# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "SidekiqRails"
rescue LoadError
end

require "sentry-rails"

# This MUST be required after sentry-rails because it requires sentry-sidekiq
# which checks if Railtie is defined to properly set things up
require_relative "../spec_helper"

# This is needed to prevent Sidekiq 6.5 crash
if Sidekiq::VERSION >= Gem::Version.new("6.5") && Sidekiq::VERSION < Gem::Version.new("7.0")
  # NoMethodError:
  #  undefined method 'broadcast' for class ActiveSupport::Logger
  #  /workspace/sentry/vendor/gems/3.4.5/gems/sidekiq-6.5.7/lib/sidekiq/rails.rb:46:in 'block (2 levels) in <class:Rails>'
  Rails.logger = Logger.new($stdout)
end

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
  app.config.eager_load = false

  app.initializer :configure_sentry do
    perform_basic_setup
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
