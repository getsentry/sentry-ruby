require 'spec_helper'
require 'contexts/with_request_mock'

RSpec.describe Sentry::HTTPTransport do
  include_context "with request mock"

  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = Sentry::TestHelper::DUMMY_DSN
      config.logger = Logger.new(nil)
    end
  end
  let(:client) { Sentry::Client.new(configuration) }
  let(:event) { client.event_from_message("foobarbaz") }
  let(:data) do
    subject.serialize_envelope(subject.envelope_from_event(event.to_hash)).first
  end

  subject { client.transport }

  it "logs a debug message only during initialization" do
    stub_request(build_fake_response("200"))
    string_io = StringIO.new
    configuration.logger = Logger.new(string_io)

    subject

    expect(string_io.string).to include("sentry: Sentry HTTP Transport will connect to http://sentry.localdomain")

    string_io.string = ""
    expect(string_io.string).to eq("")

    subject.send_data(data)

    expect(string_io.string).not_to include("sentry: Sentry HTTP Transport will connect to http://sentry.localdomain")
  end

  it "initializes new Net::HTTP instance for every request" do
    stub_request(build_fake_response("200")) do |request|
      expect(request["User-Agent"]).to eq("sentry-ruby/#{Sentry::VERSION}")
    end

    subject

    expect(Net::HTTP).to receive(:new).and_call_original.exactly(2)

    subject.send_data(data)
    subject.send_data(data)
  end

  describe "port detection" do
    let(:configuration) do
      Sentry::Configuration.new.tap do |config|
        config.dsn = dsn
        config.logger = Logger.new(nil)
      end
    end

    context "with http DSN" do
      let(:dsn) { "http://12345:67890@sentry.localdomain/sentry/42" }

      it "sets port to 80" do
        expect(subject.send(:conn).port).to eq(80)
      end
    end
    context "with http DSN" do
      let(:dsn) { "https://12345:67890@sentry.localdomain/sentry/42" }

      it "sets port to 443" do
        expect(subject.send(:conn).port).to eq(443)
      end
    end

    context "with specified port" do
      let(:dsn) { "https://12345:67890@sentry.localdomain:1234/sentry/42" }

      it "sets port to 1234" do
        expect(subject.send(:conn).port).to eq(1234)
      end
    end
  end

  describe "customizations" do
    let(:fake_response) { build_fake_response("200") }

    it 'sets default User-Agent' do
      stub_request(fake_response) do |request|
        expect(request["User-Agent"]).to eq("sentry-ruby/#{Sentry::VERSION}")
      end

      subject.send_data(data)
    end

    it "accepts custom proxy" do
      configuration.transport.proxy = { uri:  URI("https://example.com"), user: "stan", password: "foobar" }

      stub_request(fake_response) do |_, http_obj|
        expect(http_obj.proxy_address).to eq("example.com")
        expect(http_obj.proxy_user).to eq("stan")
        expect(http_obj.proxy_pass).to eq("foobar")
      end

      subject.send_data(data)
    end

    it "accepts a custom proxy string" do
      configuration.transport.proxy = "https://stan:foobar@example.com:8080"

      stub_request(fake_response) do |_, http_obj|
        expect(http_obj.proxy_address).to eq("example.com")
        expect(http_obj.proxy_user).to eq("stan")
        expect(http_obj.proxy_pass).to eq("foobar")
        expect(http_obj.proxy_port).to eq(8080)
      end

      subject.send_data(data)
    end

    it "accepts a custom proxy URI" do
      configuration.transport.proxy = URI("https://stan:foobar@example.com:8080")

      stub_request(fake_response) do |_, http_obj|
        expect(http_obj.proxy_address).to eq("example.com")
        expect(http_obj.proxy_user).to eq("stan")
        expect(http_obj.proxy_pass).to eq("foobar")
        expect(http_obj.proxy_port).to eq(8080)
      end

      subject.send_data(data)
    end

    it "accepts custom timeout" do
      configuration.transport.timeout = 10

      stub_request(fake_response) do |_, http_obj|
        expect(http_obj.read_timeout).to eq(10)

        if RUBY_VERSION >= "2.6"
          expect(http_obj.write_timeout).to eq(10)
        end
      end

      subject.send_data(data)
    end

    it "accepts custom open_timeout" do
      configuration.transport.open_timeout = 10

      stub_request(fake_response) do |_, http_obj|
        expect(http_obj.open_timeout).to eq(10)
      end

      subject.send_data(data)
    end

    describe "ssl configurations" do
      it "has the corrent default" do
        stub_request(fake_response) do |_, http_obj|
          expect(http_obj.verify_mode).to eq(1)
          expect(http_obj.ca_file).to eq(nil)
        end

        subject.send_data(data)
      end

      it "accepts custom ssl_verification configuration" do
        configuration.transport.ssl_verification = false

        stub_request(fake_response) do |_, http_obj|
          expect(http_obj.verify_mode).to eq(0)
          expect(http_obj.ca_file).to eq(nil)
        end

        subject.send_data(data)
      end

      it "accepts custom ssl_ca_file configuration" do
        configuration.transport.ssl_ca_file = "/tmp/foo"

        stub_request(fake_response) do |_, http_obj|
          expect(http_obj.verify_mode).to eq(1)
          expect(http_obj.ca_file).to eq("/tmp/foo")
        end

        subject.send_data(data)
      end

      it "accepts custom ssl configuration" do
        configuration.transport.ssl  = { verify: false, ca_file: "/tmp/foo" }

        stub_request(fake_response) do |_, http_obj|
          expect(http_obj.verify_mode).to eq(0)
          expect(http_obj.ca_file).to eq("/tmp/foo")
        end

        subject.send_data(data)
      end
    end
  end

  describe "request payload" do
    let(:fake_response) { build_fake_response("200") }

    it "compresses data by default" do
      stub_request(fake_response) do |request|
        expect(request["Content-Type"]).to eq("application/x-sentry-envelope")
        expect(request["Content-Encoding"]).to eq("gzip")

        envelope = Zlib.gunzip(request.body)
        expect(envelope).to include(event.event_id)
        expect(envelope).to include("foobarbaz")
      end

      subject.send_data(data)
    end

    it "doesn't compress small event" do
      stub_request(fake_response) do |request|
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

      stub_request(fake_response) do |request|
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
      let(:fake_response) { build_fake_response("404") }

      it 'raises an error' do
        stub_request(fake_response)

        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 404/)
      end
    end

    context "receive 5xx responses" do
      let(:fake_response) { build_fake_response("500") }

      it 'raises an error' do
        stub_request(fake_response)

        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 500/)
      end
    end

    context "receive error responses with headers" do
      let(:error_response) do
        build_fake_response("500", headers: { 'x-sentry-error' => 'error_in_header' })
      end

      it 'raises an error with header' do
        stub_request(error_response)

        expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /error_in_header/)

      end
    end
  end
end
