require 'spec_helper'
require 'raven'
require 'raven/error'
require 'logger'

describe "Integration tests" do

  example "posting an exception" do

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/store') { [200, {}, 'ok'] }
    end

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.environments = [ "test" ]
      config.current_environment = "test"
      config.http_adapter = [ :test, stubs ]
    end

    Raven.capture_exception(build_exception)

    stubs.verify_stubbed_calls

  end

  example "hitting quota limit shouldn't swallow exception" do

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/api/store') { [403, {}, 'Creation of this event was blocked'] }
    end

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.environments = [ "test" ]
      config.current_environment = "test"
      config.http_adapter = [ :test, stubs ]
    end

    Raven.logger.should_receive(:warn).exactly(1).times
    expect { Raven.capture_exception(build_exception) }.not_to raise_error(Raven::Error)

    stubs.verify_stubbed_calls

  end
end
