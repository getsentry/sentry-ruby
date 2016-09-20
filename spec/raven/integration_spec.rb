require 'spec_helper'

describe "Integration tests" do
  example "posting an exception" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [200, {}, 'ok'] }
    end
    io = StringIO.new

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.http_adapter = [:test, stubs]
      config.logger = Logger.new(io)
    end

    Raven.capture_exception(build_exception)

    stubs.verify_stubbed_calls

    expect(io.string).to match(/Sending event [0-9a-f|-]+ to Sentry$/)
  end

  example "posting an exception to a prefixed DSN" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }
    end

    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
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
      config.http_adapter = [:test, stubs]
    end

    expect(Raven.logger).to receive(:error).at_least(10).times
    Raven.capture_exception(build_exception)

    stubs.verify_stubbed_calls
  end

  example "timed backoff should prevent sends" do
    io = StringIO.new
    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.http_adapter = [:test, nil]
      config.logger = Logger.new(io)
    end

    expect_any_instance_of(Raven::Transports::HTTP).to receive(:send_event).exactly(1).times.and_raise(Faraday::Error::ConnectionFailed, "conn failed")
    2.times { Raven.capture_exception(build_exception) }
    expect(io.string).to match(/Failed to submit event: ZeroDivisionError: divided by 0$/)
  end

  example "transport failure should call transport_failure_callback" do
    io = StringIO.new
    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.http_adapter = [:test, nil]
      config.transport_failure_callback = proc { |_e| io.puts "OK!" }
    end

    expect_any_instance_of(Raven::Transports::HTTP).to receive(:send_event).exactly(1).times.and_raise(Faraday::Error::ConnectionFailed, "conn failed")
    Raven.capture_exception(build_exception)
    expect(io.string).to match(/OK!$/)
  end
end
