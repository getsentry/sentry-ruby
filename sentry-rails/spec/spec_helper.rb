# frozen_string_literal: true

require "bundler/setup"

ENV["RAILS_ENV"] = "test"

begin
  require "debug/prelude"
rescue LoadError
end

require "sentry-ruby"
require "sentry-rails"

require "simplecov"

SimpleCov.start do
  project_name "sentry-rails"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end


if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

Dir["#{__dir__}/support/**/*.rb"].each { |file| require file }

RAILS_VERSION = Rails.version.to_f

puts "\n"
puts "*"*80
puts "Running tests for Rails #{RAILS_VERSION}"
puts "*"*80
puts "\n"

# Need to be required after rails is loaded from the dummy app
require "rspec/retry"
require "rspec/rails"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include(Sentry::Rails::TestHelper)

  config.before :suite do
    Sentry::TestRailsApp.load_test_schema
  end

  config.before :each do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
    ENV.delete('SENTRY_ENVIRONMENT')
    ENV.delete('SENTRY_RELEASE')
    ENV.delete('RAILS_ENV')
    ENV.delete('RACK_ENV')
  end

  config.after :each do
    Sentry::Rails::Tracing.unsubscribe_tracing_events
    expect(Sentry::Rails::Tracing.subscribed_tracing_events).to be_empty
    Sentry::Rails::Tracing.remove_active_support_notifications_patch

    if Sentry.initialized?
      Sentry::TestHelper.clear_sentry_events
      Sentry::Rails::StructuredLogging.detach(Sentry.configuration.rails.structured_logging)
    end

    if defined?(Sentry::Rails::ActiveJobExtensions)
      Sentry::Rails::ActiveJobExtensions::SentryReporter.detach_event_handlers
    end

    reset_sentry_globals!

    Rails.application&.cleanup!
  end

  config.include ActiveJob::TestHelper, type: :job
end

def reload_send_event_job
  Sentry.send(:remove_const, "SendEventJob") if defined?(Sentry::SendEventJob)
  expect(defined?(Sentry::SendEventJob)).to eq(nil)
  load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
end
