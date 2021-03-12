require 'spec_helper'

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

  it "logs a debug message during initialization" do
    string_io = StringIO.new
    configuration.logger = Logger.new(string_io)

    subject

    expect(string_io.string).to include("sentry: Sentry HTTP Transport connecting to http://sentry.localdomain/sentry")
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
    let(:compressed_stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('sentry/api/42/envelope/') do |env|
          expect(env.request_headers["Content-Type"]).to eq("application/x-sentry-envelope")
          expect(env.request_headers["Content-Encoding"]).to eq("gzip")

          envelope = Zlib.gunzip(env.body)
          expect(envelope).to include(event.event_id)
          expect(envelope).to include("foobarbaz")
        end
      end
    end

    let(:uncompressed_stubs) do
      Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post('sentry/api/42/envelope/') do |env|
          expect(env.request_headers["Content-Type"]).to eq("application/x-sentry-envelope")
          expect(env.request_headers["Content-Encoding"]).to eq("")

          envelope = env.body
          expect(envelope).to include(event.event_id)
          expect(envelope).to include("foobarbaz")
        end
      end
    end

    it "compresses data by default" do
      configuration.transport.http_adapter = [:test, compressed_stubs]

      subject.send_data(data)
      compressed_stubs.verify_stubbed_calls
    end

    it "doesn't compress small event" do
      configuration.transport.http_adapter = [:test, uncompressed_stubs]

      event.instance_variable_set(:@threads, nil) # shrink event

      subject.send_data(data)
      uncompressed_stubs.verify_stubbed_calls
    end

    it "doesn't compress data if the encoding is not gzip" do
      configuration.transport.http_adapter = [:test, uncompressed_stubs]
      configuration.transport.encoding = "json"

      subject.send_data(data)
      uncompressed_stubs.verify_stubbed_calls
    end
  end

  describe "failed request handling" do
    before do
      configuration.transport.http_adapter = [:test, stubs]
    end

    context "receive 4xx responses" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') { [404, {}, 'not found'] }
        end
      end

      it 'raises an error' do
        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 404/)

        stubs.verify_stubbed_calls
      end
    end

    context "receive 429 response" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') do
            [
              429, headers, "{\"detail\":\"event rejected due to rate limit\"}"
            ]
          end
        end
      end

      context "with x-sentry-rate-limits header" do
        now = Time.now

        [
          {
            header: "", expected_limits: {}
          },
          {
            header: "invalid", expected_limits: {}
          },
          {
            header: ",,foo,", expected_limits: {}
          },
          {
            header: "42::organization, invalid, 4711:foobar;transaction;security:project",
            expected_limits: {
              nil => now + 42,
              "transaction" => now + 4711,
              "foobar" => now + 4711,
              "security" => now + 4711
            }
          }
        ].each do |pair|
          context "with header value: '#{pair[:header]}'" do
            let(:headers) do
              { status: 429, "x-sentry-rate-limits" => pair[:header] }
            end

            it "parses the header into correct limits" do
              Timecop.freeze(now) do
                expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 429/)
              end

              expect(subject.rate_limits).to eq(pair[:expected_limits])
            end
          end
        end
      end

      context "with retry-after header" do
        now = Time.now

        [
          {
            header: "48", expected_limits: { nil => now + 48 }
          },
          {
            header: "invalid", expected_limits: { nil => now + 60}
          },
          {
            header: "", expected_limits: { nil => now + 60}
          },
        ].each do |pair|
          context "with header value: '#{pair[:header]}'" do
            let(:headers) do
              { status: 429, "retry-after" => pair[:header] }
            end

            it "parses the header into correct limits" do
              Timecop.freeze(now) do
                expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 429/)
              end

              expect(subject.rate_limits).to eq(pair[:expected_limits])
            end
          end
        end
      end
    end

    context "receive 5xx responses" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') { [500, {}, 'error'] }
        end
      end

      it 'raises an error' do
        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 500/)

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
        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /error_in_header/)

        stubs.verify_stubbed_calls
      end
    end
  end
end
