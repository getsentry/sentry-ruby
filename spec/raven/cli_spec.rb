require 'spec_helper'
require 'raven/cli'

describe "CLI tests" do
  let(:configuration) do
    Raven::Configuration.new.tap do |config|
      config.environments = ["test"]
      config.current_environment = "test"
      config.silence_ready = true
    end
  end

  it "posting an exception" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [200, {}, 'ok'] }
    end
    configuration.http_adapter = [:test, stubs]

    dsn = 'http://12345:67890@sentry.localdomain/sentry/42'
    Raven::CLI.test(dsn, true, configuration)

    stubs.verify_stubbed_calls
  end

  it "posting an exception to a prefixed DSN" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }
    end
    configuration.http_adapter = [:test, stubs]

    dsn = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
    Raven::CLI.test(dsn, true, configuration)

    stubs.verify_stubbed_calls
  end
end
