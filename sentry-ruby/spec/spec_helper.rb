# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end
require "timecop"
require "simplecov"
require "rspec/retry"
require "redis"
require "stackprof" unless RUBY_PLATFORM == "java"
require "vernier" unless RUBY_PLATFORM == "java" || RUBY_VERSION < "3.2"

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

require "support/profiler"
require "support/stacktrace_test_fixture"

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

  config.before(:each, when: true) do |example|
    guards =
      case value = example.metadata[:when]
      when Symbol then [value]
      when Array then value
      when Hash then value.map { |k, v| [k, v].flatten }
      else
        raise ArgumentError, "Invalid `when` metadata: #{value.inspect}"
      end

    skip_examples = guards.any? do |meth, *args|
      !TestHelpers.public_send(meth, *args)
    end

    skip("Skipping because one or more guards `#{guards.inspect}` returned false") if skip_examples
  end

  RSpec::Matchers.define :have_recorded_lost_event do |reason, data_category, num: 1|
    match do |transport|
      expect(transport.discarded_events[[reason, data_category]]).to eq(num)
    end
  end
end

module TestHelpers
  def self.stack_prof_installed?
    defined?(StackProf)
  end

  def self.vernier_installed?
    require "sentry/vernier/profiler"
    defined?(::Vernier)
  end

  def self.rack_available?
    defined?(Rack)
  end

  def self.ruby_version?(op, version)
    RUBY_VERSION.public_send(op, version)
  end
end

def fixtures_root
  @fixtures_root ||= Pathname(__dir__).join("fixtures")
end

def fixture_path(name)
  fixtures_root.join(name).realpath
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
