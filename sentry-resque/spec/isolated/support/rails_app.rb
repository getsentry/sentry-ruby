# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "ResqueActiveJob"
rescue LoadError
end

ENV["RAILS_ENV"] = "test"

SENTRY_RAILS_SPEC_DIR = File.expand_path("../../../../sentry-rails/spec", __dir__)
$LOAD_PATH.unshift(SENTRY_RAILS_SPEC_DIR) unless $LOAD_PATH.include?(SENTRY_RAILS_SPEC_DIR)

require "sentry-rails"
require "sentry-resque"

require_relative "../../../../sentry-rails/spec/support/test_helper"
require_relative "../../../../sentry-rails/spec/support/test_jobs"
require "rspec/rails"
Dir["#{SENTRY_RAILS_SPEC_DIR}/active_job/support/**/*.rb"].sort.each { |file| require file }
Dir["#{SENTRY_RAILS_SPEC_DIR}/active_job/shared_examples/**/*.rb"].sort.each { |file| require file }

module ResqueTestRailsApp
  def configure
    super
    config.eager_load = false
    config.active_job.queue_adapter = :resque
  end
end

Sentry::TestRailsApp.prepend(ResqueTestRailsApp)

RAILS_VERSION = Rails.version.to_f
RESQUE_ACTIVE_JOB_ADAPTER = Sentry::Resque::ActiveJobSupport::ACTIVE_JOB_ADAPTER

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.include(Sentry::Rails::TestHelper)
  config.include(ActiveJob::TestHelper, type: :job)

  config.before(:suite) do
    Sentry::TestRailsApp.load_test_schema
  end

  config.before(:each) do
    if Sentry.initialized?
      Sentry.configuration.resque.active_job_integration = :rails
      Sentry.configuration.rails.skippable_job_adapters -= [RESQUE_ACTIVE_JOB_ADAPTER]
    end
  end

  config.after(:each) do
    Sentry::Rails::Tracing.unsubscribe_tracing_events
    Sentry::Rails::Tracing.remove_active_support_notifications_patch

    if Sentry.initialized?
      Sentry::TestHelper.clear_sentry_events
      Sentry::Rails::StructuredLogging.detach(Sentry.configuration.rails.structured_logging)
    end

    Sentry::Rails::ActiveJobExtensions::SentryReporter.detach_event_handlers

    reset_sentry_globals!

    Rails.application&.cleanup!
  end
end
