require "bundler/setup"
require "pry"

# this enables sidekiq's server mode
require "sidekiq/cli"
# require "support/test_sidekiq_app/app"

require 'simplecov'

SimpleCov.start do
  project_name "sentry-sidekiq"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

require "sentry-sidekiq"

DUMMY_DSN = 'http://12345:67890@sentry.localdomain/sentry/42'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    # Make sure we reset the env in case something leaks in
    ENV.delete('SENTRY_DSN')
    ENV.delete('SENTRY_CURRENT_ENV')
    ENV.delete('SENTRY_ENVIRONMENT')
    ENV.delete('SENTRY_RELEASE')
    ENV.delete('sidekiq_ENV')
    ENV.delete('RACK_ENV')
  end

  config.before :all do
    Sidekiq.logger = Logger.new(nil)
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

def build_exception_with_recursive_cause
  backtrace = []

  exception = double("Exception")
  allow(exception).to receive(:cause).and_return(exception)
  allow(exception).to receive(:message).and_return("example")
  allow(exception).to receive(:backtrace).and_return(backtrace)
  exception
end

class HappyWorker
  include Sidekiq::Worker

  def perform
    crumb = Sentry::Breadcrumb.new(message: "I'm happy!")
    Sentry.add_breadcrumb(crumb)
    Sentry.set_tags mood: 'happy'
  end
end

class SadWorker
  include Sidekiq::Worker

  def perform
    crumb = Sentry::Breadcrumb.new(message: "I'm sad!")
    Sentry.add_breadcrumb(crumb)
    Sentry.set_tags :mood => 'sad'

    raise "I'm sad!"
  end
end

class VerySadWorker
  include Sidekiq::Worker

  def perform
    crumb = Sentry::Breadcrumb.new(message: "I'm very sad!")
    Sentry.add_breadcrumb(crumb)
    Sentry.set_tags :mood => 'very sad'

    raise "I'm very sad!"
  end
end

class ReportingWorker
  include Sidekiq::Worker

  def perform
    Sentry.capture_message("I have something to say!")
  end
end

def process_job(processor, klass)
  msg = Sidekiq.dump_json("class" => klass)
  job = Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg)
  processor.instance_variable_set(:'@job', job)

  processor.send(:process, job)
rescue StandardError
  # do nothing
end

def perform_basic_setup
  Sentry.init do |config|
    config.dsn = DUMMY_DSN
    config.logger = ::Logger.new(nil)
    config.background_worker_threads = 0
    config.transport.transport_class = Sentry::DummyTransport
  end
end
