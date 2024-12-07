# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end

require "sentry-ruby"
require 'rspec/retry'

require 'simplecov'

SimpleCov.start do
  project_name "sentry-rails"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end


if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

# this already requires the sdk
require "dummy/test_rails_app/app"
# need to be required after rails is loaded from the above
require "rspec/rails"

DUMMY_DSN = 'http://12345:67890@sentry.localdomain/sentry/42'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after :each do
    Sentry::Rails::Tracing.unsubscribe_tracing_events
    expect(Sentry::Rails::Tracing.subscribed_tracing_events).to be_empty
    Sentry::Rails::Tracing.remove_active_support_notifications_patch
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

  config.include ActiveJob::TestHelper, type: :job
end

def reload_send_event_job
  Sentry.send(:remove_const, "SendEventJob") if defined?(Sentry::SendEventJob)
  expect(defined?(Sentry::SendEventJob)).to eq(nil)
  load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
end
