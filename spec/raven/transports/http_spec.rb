require 'spec_helper'

describe Raven::Transports::HTTP do
  before do
    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
  end

  it 'should set a custom User-Agent' do
    expect(Raven.client.send(:transport).conn.headers[:user_agent]).to eq("sentry-ruby/#{Raven::VERSION}")
  end

  it 'should raise an error on 4xx responses' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [404, {}, 'not found'] }
    end
    Raven.configure { |config| config.http_adapter = [:test, stubs] }

    event = JSON.generate(Raven::Event.from_message("test").to_hash)
    expect { Raven.client.send(:transport).send_event("test", event) }.to raise_error(Raven::Error)

    stubs.verify_stubbed_calls
  end

  it 'should raise an error on 5xx responses' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [500, {}, 'error'] }
    end
    Raven.configure { |config| config.http_adapter = [:test, stubs] }

    event = JSON.generate(Raven::Event.from_message("test").to_hash)
    expect { Raven.client.send(:transport).send_event("test", event) }.to raise_error(Raven::Error)

    stubs.verify_stubbed_calls
  end

  it 'should add header info message to the error' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [400, { 'x-sentry-error' => 'error_in_header' }, 'error'] }
    end
    Raven.configure { |config| config.http_adapter = [:test, stubs] }

    event = JSON.generate(Raven::Event.from_message("test").to_hash)
    expect { Raven.client.send(:transport).send_event("test", event) }.to raise_error(Raven::Error, /error_in_header/)

    stubs.verify_stubbed_calls
  end

  it 'allows to customise faraday' do
    builder = spy('faraday_builder')
    expect(Faraday).to receive(:new).and_yield(builder)

    Raven.configure do |config|
      config.faraday_builder = proc { |b| b.request :instrumentation }
    end

    Raven.client.send(:transport)

    expect(builder).to have_received(:request).with(:instrumentation)
  end
end
