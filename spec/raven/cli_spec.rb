require 'spec_helper'

describe "CLI tests" do
  example "posting an exception" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [200, {}, 'ok'] }
    end

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.environments = ["test"]
      config.current_environment = "test"
      config.http_adapter = [:test, stubs]
    end

    expect { Raven::CLI.test }.not_to raise_error

    stubs.verify_stubbed_calls
  end

  example "posting an exception to a prefixed DSN" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }
    end

    Raven.configure do |config|
      config.environments = ["test"]
      config.current_environment = "test"
      config.http_adapter = [:test, stubs]
    end

    expect {
      Raven::CLI.test 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
    }.not_to raise_error

    stubs.verify_stubbed_calls
  end
end
