# typed: false
require 'spec_helper'

RSpec.describe Sentry::Transports::HTTP do
  let(:config) do
    Sentry::Configuration.new.tap do |c|
      c.dsn = 'http://12345@sentry.localdomain/sentry/42'
      c.http_adapter = [:test, stubs]
    end
  end

  let(:client) { Sentry::Client.new(config) }
  let(:event) { client.event_from_message("test") }

  describe "customizations" do
    let(:config) do
      Sentry::Configuration.new.tap do |c|
        c.dsn = 'http://12345@sentry.localdomain/sentry/42'
      end
    end

    it 'sets a custom User-Agent' do
      expect(client.transport.conn.headers[:user_agent]).to eq("sentry-ruby/#{Sentry::VERSION}")
    end

    it 'allows to customise faraday' do
      builder = spy('faraday_builder')
      expect(Faraday).to receive(:new).and_yield(builder)
      config.faraday_builder = proc { |b| b.request :instrumentation }

      client.transport

      expect(builder).to have_received(:request).with(:instrumentation)
    end
  end

  context "receive 4xx responses" do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('sentry/api/42/store/') { [404, {}, 'not found'] }
      end
    end

    it 'raises an error' do
      expect { client.transport.send_event("fake auth", event) }.to raise_error(Sentry::Error, /the server responded with status 404/)

      stubs.verify_stubbed_calls
    end
  end

  context "receive 5xx responses" do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('sentry/api/42/store/') { [500, {}, 'error'] }
      end
    end

    it 'raises an error' do
      expect { client.transport.send_event("fake auth", event) }.to raise_error(Sentry::Error, /the server responded with status 500/)

      stubs.verify_stubbed_calls
    end
  end

  context "receive error responses with headers" do
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('sentry/api/42/store/') { [400, { 'x-sentry-error' => 'error_in_header' }, 'error'] }
      end
    end

    it 'raises an error with header' do
      expect { client.transport.send_event("fake auth", event) }.to raise_error(Sentry::Error, /error_in_header/)

      stubs.verify_stubbed_calls
    end
  end
end
