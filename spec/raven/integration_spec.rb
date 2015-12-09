require 'spec_helper'

describe "Integration tests" do
  example "posting an exception" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [200, {}, 'ok'] }
    end
    io = StringIO.new

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.environments = ["test"]
      config.current_environment = "test"
      config.http_adapter = [:test, stubs]
      config.logger = Logger.new(io)
    end

    Raven.capture_exception(build_exception)

    stubs.verify_stubbed_calls

    expect(io.string).to match(/Sending event [0-9a-f]+ to Sentry$/)
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

    expect(Raven.logger).to receive(:warn).once
    expect { Raven.capture_exception(build_exception) }.not_to raise_error

    stubs.verify_stubbed_calls
  end

  example "timed backoff should prevent sends" do
    io = StringIO.new
    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.environments = ["test"]
      config.current_environment = "test"
      config.http_adapter = [:test, nil]
      config.logger = Logger.new(io)
    end

    expect_any_instance_of(Raven::Transports::HTTP).to receive(:send_event).exactly(1).times.and_raise(Faraday::Error::ConnectionFailed, "conn failed")
    expect { Raven.capture_exception(build_exception) }.not_to raise_error

    expect(Raven.logger).to receive(:error).exactly(1).times
    expect { Raven.capture_exception(build_exception) }.not_to raise_error
    expect(io.string).to match(/Failed to submit event: ZeroDivisionError: divided by 0$/)
  end
end
