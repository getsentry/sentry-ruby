require "bundler/setup"
require "debug" if RUBY_VERSION.to_f >= 2.6 && RUBY_ENGINE == "ruby"
require "pry"
require "timecop"
require "simplecov"
require "rspec/retry"
require "redis"
require "stackprof" unless RUBY_PLATFORM == "java"

SimpleCov.start do
  project_name "sentry-ruby"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "sentry-ruby"
require "sentry/test_helper"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.include(Sentry::TestHelper)

  config.expect_with :rspec do |c|
    c.syntax = :expect
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

  config.before(:each, rack: true) do
    skip("skip rack related tests") unless defined?(Rack)
  end

  RSpec::Matchers.define :have_recorded_lost_event do |reason, type|
    match do |transport|
      expect(transport.discarded_events[[reason, type]]).to be > 0
    end
  end
end

def build_exception_with_cause(cause = "exception a")
  begin
    raise cause
  rescue
    raise "exception b"
  end
rescue RuntimeError => e
  e
end

def build_exception_with_two_causes
  begin
    begin
      raise "exception a"
    rescue
      raise "exception b"
    end
  rescue
    raise "exception c"
  end
rescue RuntimeError => e
  e
end

def build_exception_with_recursive_cause
  backtrace = []

  exception = double("Exception")
  allow(exception).to receive(:cause).and_return(exception)
  allow(exception).to receive(:message).and_return("example")
  allow(exception).to receive(:backtrace).and_return(backtrace)
  exception
end

def perform_basic_setup
  Sentry.init do |config|
    config.logger = Logger.new(nil)
    config.dsn = Sentry::TestHelper::DUMMY_DSN
    config.transport.transport_class = Sentry::DummyTransport
    # so the events will be sent synchronously for testing
    config.background_worker_threads = 0
    yield(config) if block_given?
  end
end
