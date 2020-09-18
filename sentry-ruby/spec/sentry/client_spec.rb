require 'spec_helper'

class ExceptionWithContext < StandardError
  def sentry_context
    { extra: {
      'context_event_key' => 'context_value',
      'context_key' => 'context_value'
    } }
  end
end

RSpec.describe Sentry::Client do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
  end
  let(:client) { Sentry::Client.new(configuration) }
  subject { client }

  before do
    @fake_time = Time.now
    allow(Time).to receive(:now).and_return @fake_time
  end

  describe "#generate_auth_header" do
    it "generates an auth header" do
      expect(client.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{@fake_time.to_i}, " \
        "sentry_key=12345, sentry_secret=67890"
      )
    end

    it "generates an auth header without a secret (Sentry 9)" do
      configuration.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"

      expect(client.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{@fake_time.to_i}, " \
        "sentry_key=66260460f09b5940498e24bb7ce093a0"
      )
    end
  end

  # it "generates a message with exception" do
  #   event = Sentry.capture_exception(ZeroDivisionError.new("divided by 0")).to_hash
  #   expect(client.send(:get_message_from_exception, event)).to eq("ZeroDivisionError: divided by 0")
  # end

  # it "generates a message without exception" do
  #   event = Sentry.event_from_message("this is an STDOUT transport test").to_hash
  #   expect(client.send(:get_message_from_exception, event)).to eq(nil)
  # end

  # describe "#send_event" do
  #   let(:event) { subject.event_from_exception(ZeroDivisionError.new("divided by 0")) }

  #   context "when success" do
  #     before do
  #       allow(client.transport).to receive(:send_event)
  #     end

  #     it "sends Event object" do
  #       expect(client).not_to receive(:failed_send)

  #       expect(client.send_event(event)).to eq(event.to_hash)
  #     end

  #     it "sends Event hash" do
  #       expect(client).not_to receive(:failed_send)

  #       expect(client.send_event(event.to_json_compatible)).to eq(event.to_json_compatible)
  #     end
  #   end

  #   context "when failed" do
  #     let(:logger) { spy }

  #     before do
  #       configuration.logger = logger
  #       allow(client.transport).to receive(:send_event).and_raise(StandardError)

  #       expect(logger).to receive(:warn).exactly(2)
  #     end

  #     it "sends Event object" do
  #       expect(client.send_event(event)).to eq(nil)
  #     end

  #     it "sends Event hash" do
  #       expect(client.send_event(event.to_json_compatible)).to eq(nil)
  #     end
  #   end
  # end

  describe "#transport" do
    context "when scheme is not set" do
      it "returns HTTP transport object" do
        expect(client.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is http" do
      before do
        configuration.scheme = "http"
      end

      it "returns HTTP transport object" do
        expect(client.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is https" do
      before do
        configuration.scheme = "https"
      end

      it "returns HTTP transport object" do
        expect(client.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is dummy" do
      before do
        configuration.scheme = "dummy"
      end

      it "returns Dummy transport object" do
        expect(client.transport).to be_a(Sentry::Transports::Dummy)
      end
    end

    context "when scheme is stdout" do
      before do
        configuration.scheme = "stdout"
      end

      it "returns Stdout transport object" do
        expect(client.transport).to be_a(Sentry::Transports::Stdout)
      end
    end
  end

  describe '#event_from_message' do
    let(:message) { 'This is a message' }

    it 'returns an event' do
      event = subject.event_from_message(message)
      hash = event.to_hash

      expect(event).to be_a(Sentry::Event)
      expect(hash[:message]).to eq(message)
      expect(hash[:level]).to eq(:error)
    end

    it "doesn't change the option hash" do
      h_int = { abc: :abc }
      h = { k1: h_int, k2: h_int }
      subject.event_from_message "Test extra", extra: { h1: h, h2: h_int }

      expect(h).to eq({ k1: h_int, k2: h_int })
    end

    describe "backtrace" do
      let(:backtrace) do
        ["/path/to/some/file:22:in `function_name'", "/some/other/path:1412:in `other_function'"]
      end

      it "contains given backtrace" do
        event = subject.event_from_message(message, backtrace: backtrace)

        expect(event[:stacktrace]).to be_a(Sentry::StacktraceInterface)

        frames = event[:stacktrace].to_hash[:frames]
        expect(frames.length).to eq(2)
        expect(frames[0][:lineno]).to eq(1412)
        expect(frames[0][:function]).to eq('other_function')
        expect(frames[0][:filename]).to eq('/some/other/path')

        expect(frames[1][:lineno]).to eq(22)
        expect(frames[1][:function]).to eq('function_name')
        expect(frames[1][:filename]).to eq('/path/to/some/file')
      end
    end
  end

  describe "#event_from_exception" do
    before do
      configuration.scheme = "dummy"
    end

    it 'returns an event' do
      expect(subject.event_from_exception(ExceptionWithContext.new)).to be_a(Sentry::Event)
    end

    describe "message" do
      it "proceses string message correctly" do
        event = subject.event_from_exception(ExceptionWithContext.new, message: "MSG")
        expect(event.message).to eq("MSG")
      end

      it "slices long string message" do
        event = subject.event_from_exception(ExceptionWithContext.new, message: "MSG" * 3000)
        expect(event.message.length).to eq(8192)
      end

      it "converts non-string message into string" do
        expect(configuration.logger).to receive(:debug).with("You're passing a non-string message")

        event = subject.event_from_exception(ExceptionWithContext.new, message: { foo: "bar" })
        expect(event.message).to eq("{:foo=>\"bar\"}")
      end
    end

    describe "backtrace" do
      let(:backtrace) do
        ["/path/to/some/file:22:in `function_name'", "/some/other/path:1412:in `other_function'"]
      end

      it "contains given backtrace" do
        event = subject.event_from_exception(ExceptionWithContext.new, backtrace: backtrace)

        expect(event[:stacktrace]).to be_a(Sentry::StacktraceInterface)

        frames = event[:stacktrace].to_hash[:frames]
        expect(frames.length).to eq(2)
        expect(frames[0][:lineno]).to eq(1412)
        expect(frames[0][:function]).to eq('other_function')
        expect(frames[0][:filename]).to eq('/some/other/path')

        expect(frames[1][:lineno]).to eq(22)
        expect(frames[1][:function]).to eq('function_name')
        expect(frames[1][:filename]).to eq('/path/to/some/file')
      end

    end

    context 'merging exception context' do
      let(:hash) do
        event = subject.event_from_exception(
          ExceptionWithContext.new,
          message: "MSG",
          extra: {
            'context_event_key' => 'event_value',
            'event_key' => 'event_value'
          }
        )
        event.to_hash
      end

      it 'prioritizes event context over request context' do
        expect(hash[:extra]['context_event_key']).to eq('event_value')
        expect(hash[:extra]['context_key']).to eq('context_value')
        expect(hash[:extra]['event_key']).to eq('event_value')
      end
    end
  end
end
