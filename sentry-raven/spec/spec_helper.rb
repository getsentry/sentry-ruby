require 'sentry_raven_without_integrations'
require 'pry'

require 'simplecov'
SimpleCov.start

if ENV["CI"]
  require 'codecov'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

Raven.configure do |config|
  config.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"
  config.encoding = "json"
  config.silence_ready = true
  config.logger = Logger.new(nil)
end

if ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 0)
  RSpec.configure do |config|
    config.filter_run_excluding :rails => true
  end
else
  require File.dirname(__FILE__) + "/support/test_rails_app/app.rb"
  require "rspec/rails"
end

RSpec.configure do |config|
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
  config.disable_monkey_patching!
  Kernel.srand config.seed
end

RSpec.shared_examples "Raven default capture behavior" do
  it "captures exceptions" do
    expect { block }.to raise_error(captured_class)

    expect(Raven.client.transport.events.size).to eq(1)

    event = JSON.parse!(Raven.client.transport.events.first[1])
    expect(event["exception"]["values"][0]["type"]).to eq(captured_class.name)
    expect(event["exception"]["values"][0]["value"]).to eq(captured_message)
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
