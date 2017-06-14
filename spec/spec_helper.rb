require 'sentry-raven-without-integrations'

require File.dirname(__FILE__) + "/support/test_rails_app/app.rb"
require "rspec/rails"
require 'raven/transports/dummy'

RSpec.configure do |config|
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

def build_exception
  1 / 0
rescue ZeroDivisionError => exception
  return exception
end

def build_exception_with_cause
  begin
    raise "exception a"
  rescue
    raise "exception b"
  end
rescue RuntimeError => exception
  return exception
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
rescue RuntimeError => exception
  return exception
end

def build_exception_with_recursive_cause
  backtrace = []

  exception = double("Exception")
  allow(exception).to receive(:cause).and_return(exception)
  allow(exception).to receive(:message).and_return("example")
  allow(exception).to receive(:backtrace).and_return(backtrace)
  exception
end
