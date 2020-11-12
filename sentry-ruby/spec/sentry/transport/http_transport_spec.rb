require 'spec_helper'

RSpec.describe Sentry::HTTPTransport do
  let(:client) { Sentry::Client.new(Sentry.configuration) }
  let(:event) { client.event_from_message("test") }
  subject { described_class.new(Sentry.configuration) }

  describe "customizations" do
    before do
      Sentry.init do |c|
        c.dsn = 'http://12345@sentry.localdomain/sentry/42'
      end
    end

    it 'sets a custom User-Agent' do
      expect(subject.conn.headers[:user_agent]).to eq("sentry-ruby/#{Sentry::VERSION}")
    end

    it 'allows to customise faraday' do
      builder = spy('faraday_builder')
      expect(Faraday).to receive(:new).and_yield(builder)
      Sentry.configuration.transport.faraday_builder = proc { |b| b.request :instrumentation }

      subject

      expect(builder).to have_received(:request).with(:instrumentation)
    end
  end

  describe "failed request handling" do
    before do
      Sentry.init do |c|
        c.dsn = 'http://12345@sentry.localdomain/sentry/42'
        c.transport.http_adapter = [:test, stubs]
        c.transport.transport_class = described_class
      end
    end
    context "receive 4xx responses" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') { [404, {}, 'not found'] }
        end
      end

      it 'raises an error' do
        expect { subject.send_data(event.to_hash) }.to raise_error(Sentry::Error, /the server responded with status 404/)

        stubs.verify_stubbed_calls
      end
    end

    context "receive 5xx responses" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') { [500, {}, 'error'] }
        end
      end

      it 'raises an error' do
        expect { subject.send_data(event.to_hash) }.to raise_error(Sentry::Error, /the server responded with status 500/)

        stubs.verify_stubbed_calls
      end
    end

    context "receive error responses with headers" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') { [400, { 'x-sentry-error' => 'error_in_header' }, 'error'] }
        end
      end

      it 'raises an error with header' do
        expect { subject.send_data(event.to_hash) }.to raise_error(Sentry::Error, /error_in_header/)

        stubs.verify_stubbed_calls
      end
    end
  end
end
