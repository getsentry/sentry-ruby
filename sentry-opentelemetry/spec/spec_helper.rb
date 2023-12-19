# frozen_string_literal: true

require "bundler/setup"
require "pry"
require "debug" if RUBY_VERSION.to_f >= 2.6 && RUBY_ENGINE == "ruby"

require 'simplecov'

SimpleCov.start do
  project_name "sentry-opentelemetry"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "sentry-ruby"
require "sentry/test_helper"
require "sentry-opentelemetry"
require "opentelemetry/sdk"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

def perform_basic_setup
  Sentry.init do |config|
    config.logger = Logger.new(nil)
    config.dsn = Sentry::TestHelper::DUMMY_DSN
    config.transport.transport_class = Sentry::DummyTransport
    # so the events will be sent synchronously for testing
    config.background_worker_threads = 0
    config.instrumenter = :otel
    config.traces_sample_rate = 1.0
    yield(config) if block_given?
  end
end

def perform_otel_setup
  ::OpenTelemetry::SDK.configure do |c|
    # suppress otlp warnings
    c.logger = Logger.new(File::NULL)
  end
end
