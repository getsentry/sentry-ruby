require 'spec_helper'

describe "Integration tests" do

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

    Raven.capture_exception(build_exception)

    stubs.verify_stubbed_calls

  end

  example "posting an exception to a prefixed DSN" do

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }
    end

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
      config.environments = ["test"]
      config.current_environment = "test"
      config.http_adapter = [:test, stubs]
    end

    Raven.capture_exception(build_exception)

    stubs.verify_stubbed_calls
  end

  example "hitting quota limit shouldn't swallow exception" do

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [403, {}, 'Creation of this event was blocked'] }
    end

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.environments = ["test"]
      config.current_environment = "test"
      config.http_adapter = [:test, stubs]
    end

    expect(Raven.logger).to receive(:warn).exactly(1).times
    expect { Raven.capture_exception(build_exception) }.not_to raise_error

    stubs.verify_stubbed_calls

  end
end
