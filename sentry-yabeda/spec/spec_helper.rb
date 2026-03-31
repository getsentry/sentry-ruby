# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end

require "sentry-ruby"
require "sentry/test_helper"

require 'simplecov'

SimpleCov.start do
  project_name "sentry-yabeda"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "sentry-yabeda"

DUMMY_DSN = 'http://12345:67890@sentry.localdomain/sentry/42'

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
    ENV.delete('SENTRY_ENVIRONMENT')
    ENV.delete('SENTRY_RELEASE')
  end

  config.include(Sentry::TestHelper)

  config.after :each do
    reset_sentry_globals!
  end
end

def perform_basic_setup
  Sentry.init do |config|
    config.dsn = DUMMY_DSN
    config.sdk_logger = ::Logger.new(nil)
    config.background_worker_threads = 0
    config.transport.transport_class = Sentry::DummyTransport
    config.enable_metrics = true

    yield config if block_given?
  end
end
