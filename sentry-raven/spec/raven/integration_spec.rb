require 'spec_helper'

RSpec.describe "Integration tests" do
  before(:each) do
    @io = StringIO.new
    @logger = Logger.new(@io)
    @instance = Raven::Instance.new
    @stubs = Faraday::Adapter::Test::Stubs.new
    @instance.configuration = Raven::Configuration.new.tap do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
      config.http_adapter = [:test, @stubs]
      config.logger = @logger
    end
  end

  it "prints deprecation warning when requiring 'sentry-raven-without-integrations'" do
    expect do
      require "sentry-raven-without-integrations"
    end.to output(
      "[Deprecation Warning] Dasherized filename \"sentry-raven-without-integrations\" is deprecated and will be removed in 4.0; use \"sentry_raven_without_integrations\" instead\n" # rubocop:disable Style/LineLength
    ).to_stderr
  end

  it "posting an exception" do
    @stubs.post('sentry/api/42/store/') { [200, {}, 'ok'] }

    @instance.capture_exception(build_exception)

    @stubs.verify_stubbed_calls
    expect(@io.string).to match(/Sending event [0-9a-f]+ to Sentry$/)
  end

  it "posting an exception to a prefixed DSN" do
    @stubs.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }
    @instance.configuration.server = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'

    @instance.capture_exception(build_exception)

    @stubs.verify_stubbed_calls
  end

  # TODO: Not a very good test
  # it "hitting quota limit shouldn't swallow exception" do
  #   @stubs.post('sentry/api/42/store/') { [403, {}, 'Creation of this event was blocked'] }
  #
  #   # sentry error and original error
  #   expect(@logger).not_to receive(:error)
  #   @instance.capture_exception(build_exception)
  #
  #   @stubs.verify_stubbed_calls
  # end

  it "timed backoff should prevent sends" do
    expect(@instance.client.transport).to receive(:send_event).exactly(1).times.and_raise(Faraday::ConnectionFailed, "conn failed")
    2.times { @instance.capture_exception(build_exception) }
    expect(@io.string).to match(/Failed to submit event: ZeroDivisionError: divided by 0$/)
  end

  it "transport failure should call transport_failure_callback" do
    @instance.configuration.transport_failure_callback = proc { |_event, error| @io.puts "OK! - #{error.message}" }

    expect(@instance.client.transport).to receive(:send_event).exactly(1).times.and_raise(Faraday::ConnectionFailed, "conn failed")
    @instance.capture_exception(build_exception)
    expect(@io.string).to match(/OK! - conn failed$/)
  end

  describe '#before_send' do
    it "change event before sending (capture_exception)" do
      @stubs.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }

      @instance.configuration.server = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
      @instance.configuration.before_send = lambda { |event, hint|
        expect(hint[:exception]).not_to be nil
        expect(hint[:message]).to be nil
        event.environment = 'testxx'
        event
      }

      event = @instance.capture_exception(build_exception)
      expect(event.environment).to eq('testxx')

      @stubs.verify_stubbed_calls
    end

    it "change event before sending (capture_message)" do
      @stubs.post('/prefix/sentry/api/42/store/') { [200, {}, 'ok'] }

      @instance.configuration.server = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
      @instance.configuration.before_send = lambda { |event, hint|
        expect(hint[:exception]).to be nil
        expect(hint[:message]).not_to be nil
        expect(event.message).to eq('xyz')
        event.message = 'abc'
        event
      }

      event = @instance.capture_message('xyz')
      expect(event.message).to eq('abc')

      @stubs.verify_stubbed_calls
    end

    it "return nil" do
      @instance.configuration.server = 'http://12345:67890@sentry.localdomain/prefix/sentry/42'
      @instance.configuration.before_send = lambda { |_event, _hint|
        nil
      }

      @instance.capture_exception(build_exception)
      expect(@instance.client.transport).to receive(:send_event).exactly(0)
    end
  end
end
