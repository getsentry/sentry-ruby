# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end

require "active_job"
require "good_job"

require "sentry-ruby"
require "sentry/test_helper"

# Fixing crash:
# activesupport-6.1.7.10/lib/active_support/logger_thread_safe_level.rb:16:in
# . `<module:LoggerThreadSafeLevel>': uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger (NameError)
require "logger"

require 'simplecov'

SimpleCov.start do
  project_name "sentry-good_job"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "sentry-good_job"

DUMMY_DSN = 'http://12345:67890@sentry.localdomain/sentry/42'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :suite do
    puts "\n"
    puts "*" * 100
    puts "Running with Good Job #{GoodJob::VERSION}"
    puts "*" * 100
    puts "\n"
  end

  config.before :each do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
    ENV.delete('SENTRY_ENVIRONMENT')
    ENV.delete('SENTRY_RELEASE')
    ENV.delete('RACK_ENV')
  end

  config.include(Sentry::TestHelper)

  config.after :each do
    reset_sentry_globals!
  end
end

def build_exception
  1 / 0
rescue ZeroDivisionError => e
  e
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

class HappyJob < ActiveJob::Base
  def perform
    crumb = Sentry::Breadcrumb.new(message: "I'm happy!")
    Sentry.add_breadcrumb(crumb)
    Sentry.set_tags mood: 'happy'
  end
end

class SadJob < ActiveJob::Base
  def perform
    crumb = Sentry::Breadcrumb.new(message: "I'm sad!")
    Sentry.add_breadcrumb(crumb)
    Sentry.set_tags mood: 'sad'

    raise "I'm sad!"
  end
end

class VerySadJob < ActiveJob::Base
  def perform
    crumb = Sentry::Breadcrumb.new(message: "I'm very sad!")
    Sentry.add_breadcrumb(crumb)
    Sentry.set_tags mood: 'very sad'

    raise "I'm very sad!"
  end
end

class ReportingJob < ActiveJob::Base
  def perform
    Sentry.capture_message("I have something to say!")
  end
end

class HappyJobWithCron < HappyJob
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins
end

class SadJobWithCron < SadJob
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins slug: "failed_job", monitor_config: Sentry::Cron::MonitorConfig.from_crontab("5 * * * *")
end

class WorkloadJob < ActiveJob::Base
  def perform
    # Create some CPU work that should show up in the profile
    calculate_fibonacci(25)
    sleep_and_sort
    generate_strings
  end

  private

  def calculate_fibonacci(n)
    return n if n <= 1
    calculate_fibonacci(n - 1) + calculate_fibonacci(n - 2)
  end

  def sleep_and_sort
    # Mix of CPU and IO work
    sleep(0.01)
    array = (1..1000).to_a.shuffle
    array.sort
  end

  def generate_strings
    # Memory and CPU work
    100.times do |i|
      "test string #{i}" * 100
      Math.sqrt(i * 1000)
    end
  end
end

def perform_basic_setup
  Sentry.init do |config|
    config.dsn = DUMMY_DSN
    config.sdk_logger = ::Logger.new(nil)
    config.background_worker_threads = 0
    config.transport.transport_class = Sentry::DummyTransport
    yield config if block_given?
  end
end
