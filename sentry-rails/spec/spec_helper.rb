require "bundler/setup"
require "pry"

require "sentry-ruby"
require 'rspec/retry'

require 'simplecov'

SimpleCov.start do
  project_name "sentry-rails"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

# this already requires the sdk
require "support/test_rails_app/app"
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

  config.before :each, :subscriber do
    Sentry::Rails::Tracing.patch_active_support_notifications
  end

  config.after :each, :subscriber do
    Sentry::Rails::Tracing.unsubscribe_tracing_events
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

def reload_send_event_job
  Sentry.send(:remove_const, "SendEventJob") if defined?(Sentry::SendEventJob)
  expect(defined?(Sentry::SendEventJob)).to eq(nil)
  load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
end

def perform_basic_setup
  Sentry.init do |config|
    config.dsn = DUMMY_DSN
    config.logger = ::Logger.new(nil)
    config.transport.transport_class = Sentry::DummyTransport
    # for sending events synchronously
    config.background_worker_threads = 0
  end
end
