require 'spec_helper'
require "webmock"

RSpec.describe Sentry::HTTPTransport do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = DUMMY_DSN
      config.logger = Logger.new(nil)
    end
  end
  let(:client) { Sentry::Client.new(configuration) }
  let(:event) { client.event_from_message("foobarbaz") }
  let(:data) do
    subject.encode(event.to_hash)
  end

  subject { described_class.new(configuration) }

  before { stub_const('Net::BufferedIO', Net::WebMockNetBufferedIO) }

  class FakeSocket < StringIO
    def setsockopt(*args); end
  end

  before do
    allow(TCPSocket).to receive(:open).and_return(FakeSocket.new)
  end

  def mock_request(fake_response, &block)
    allow(fake_response).to receive(:body).and_return(JSON.generate({ data: "success" }))
    allow_any_instance_of(Net::HTTP).to receive(:transport_request) do |_, request|
      block.call(request) if block
    end.and_return(fake_response)
  end

  it "logs a debug message during initialization" do
    string_io = StringIO.new
    configuration.logger = Logger.new(string_io)

    subject

    expect(string_io.string).to include("sentry: Sentry HTTP Transport connecting to http://sentry.localdomain")
  end

  describe "customizations" do
    it 'sets a custom User-Agent' do
      expect(subject.conn.headers[:user_agent]).to eq("sentry-ruby/#{Sentry::VERSION}")
    end

    it 'allows to customise faraday' do
      builder = spy('faraday_builder')
      expect(Faraday).to receive(:new).and_yield(builder)
      configuration.transport.faraday_builder = proc { |b| b.request :instrumentation }

      subject

      expect(builder).to have_received(:request).with(:instrumentation)
    end
  end

  describe "request payload" do
    let(:fake_response) { Net::HTTPResponse.new("1.0", "200", "") }

    it "compresses data by default" do
      mock_request(fake_response) do |request|
        expect(request["Content-Type"]).to eq("application/x-sentry-envelope")
        expect(request["Content-Encoding"]).to eq("gzip")

        envelope = Zlib.gunzip(request.body)
        expect(envelope).to include(event.event_id)
        expect(envelope).to include("foobarbaz")
      end

      subject.send_data(data)
    end

    it "doesn't compress small event" do
      mock_request(fake_response) do |request|
        expect(request["Content-Type"]).to eq("application/x-sentry-envelope")
        expect(request["Content-Encoding"]).to eq("")

        envelope = request.body
        expect(envelope).to include(event.event_id)
        expect(envelope).to include("foobarbaz")
      end

      event.instance_variable_set(:@threads, nil) # shrink event

      subject.send_data(data)
    end

    it "doesn't compress data if the encoding is not gzip" do
      configuration.transport.encoding = "json"

      mock_request(fake_response) do |request|
        expect(request["Content-Type"]).to eq("application/x-sentry-envelope")
        expect(request["Content-Encoding"]).to eq("")

        envelope = request.body
        expect(envelope).to include(event.event_id)
        expect(envelope).to include("foobarbaz")
      end

      subject.send_data(data)
    end
  end

  describe "failed request handling" do
    context "receive 4xx responses" do
      let(:not_found_response) { Net::HTTPResponse.new("1.0", "404", "") }

      it 'raises an error' do
        mock_request(not_found_response)

        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 404/)
      end
    end

    context "receive 5xx responses" do
      let(:error_response) { Net::HTTPResponse.new("1.0", "500", "") }

      it 'raises an error' do
        mock_request(error_response)

        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 500/)
      end
    end

    context "receive error responses with headers" do
      let(:error_response) do
        Net::HTTPResponse.new("1.0", "500", "").tap do |response|
          response['x-sentry-error'] = 'error_in_header'
        end
      end

      it 'raises an error with header' do
        mock_request(error_response)

        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /error_in_header/)

      end
    end
  end
end
