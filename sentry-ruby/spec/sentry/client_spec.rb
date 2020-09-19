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
  let(:fake_time) { Time.now }

  subject { Sentry::Client.new(configuration) }

  before do
    allow(Time).to receive(:now).and_return fake_time
  end

  describe "#generate_auth_header" do
    it "generates an auth header" do
      expect(subject.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{fake_time.to_i}, " \
        "sentry_key=12345, sentry_secret=67890"
      )
    end

    it "generates an auth header without a secret (Sentry 9)" do
      configuration.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"

      expect(subject.send(:generate_auth_header)).to eq(
        "Sentry sentry_version=5, sentry_client=sentry-ruby/#{Sentry::VERSION}, sentry_timestamp=#{fake_time.to_i}, " \
        "sentry_key=66260460f09b5940498e24bb7ce093a0"
      )
    end
  end

  describe "#send_event" do
    let(:event) { subject.event_from_exception(ZeroDivisionError.new("divided by 0")) }

    context "when success" do
      before do
        allow(subject.transport).to receive(:send_event)
      end

      it "sends Event object" do
        expect(subject).not_to receive(:failed_send)

        expect(subject.send_event(event)).to eq(event.to_hash)
      end

      it "sends Event hash" do
        expect(subject).not_to receive(:failed_send)

        expect(subject.send_event(event.to_json_compatible)).to eq(event.to_json_compatible)
      end
    end

    context "when failed" do
      let(:logger) { spy }

      before do
        configuration.logger = logger
        allow(subject.transport).to receive(:send_event).and_raise(StandardError)

        expect(logger).to receive(:warn).exactly(2)
      end

      it "sends Event object" do
        expect(subject.send_event(event)).to eq(nil)
      end

      it "sends Event hash" do
        expect(subject.send_event(event.to_json_compatible)).to eq(nil)
      end
    end
  end

  describe "#transport" do
    context "when scheme is not set" do
      it "returns HTTP transport object" do
        expect(subject.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is http" do
      before do
        configuration.scheme = "http"
      end

      it "returns HTTP transport object" do
        expect(subject.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is https" do
      before do
        configuration.scheme = "https"
      end

      it "returns HTTP transport object" do
        expect(subject.transport).to be_a(Sentry::Transports::HTTP)
      end
    end

    context "when scheme is dummy" do
      before do
        configuration.scheme = "dummy"
      end

      it "returns Dummy transport object" do
        expect(subject.transport).to be_a(Sentry::Transports::Dummy)
      end
    end

    context "when scheme is stdout" do
      before do
        configuration.scheme = "stdout"
      end

      it "returns Stdout transport object" do
        expect(subject.transport).to be_a(Sentry::Transports::Stdout)
      end
    end
  end

  shared_examples "options" do
    let(:options) do
      {
        checksum: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        release: '1.0',
        fingerprint: ['{{ default }}', 'foo'],
        backtrace: ["/path/to/some/file:22:in `function_name'", "/some/other/path:1412:in `other_function'"]
      }
    end

    let(:event) do
      subject.event_from_exception(Exception.new, **options)
    end

    it 'takes and sets all available options' do
      expect(event.checksum).to eq('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      expect(event.release).to eq('1.0')
      expect(event.fingerprint).to eq(['{{ default }}', 'foo'])
    end

    it "contains given backtrace" do
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

    it_behaves_like "options"
  end

  describe "#event_from_exception" do
    let(:message) { 'This is a message' }
    let(:exception) { Exception.new(message) }
    let(:event) { subject.event_from_exception(exception) }
    let(:hash) { event.to_hash }

    before do
      configuration.scheme = "dummy"
    end

    it "sets the message to the exception's value and type" do
      expect(hash[:exception][:values][0][:type]).to eq("Exception")
      expect(hash[:exception][:values][0][:value]).to eq(message)
    end

    it 'has level ERROR' do
      expect(hash[:level]).to eq(:error)
    end

    it 'does not belong to a module' do
      expect(hash[:exception][:values][0][:module]).to eq('')
    end

    it 'returns an event' do
      event = subject.event_from_exception(ZeroDivisionError.new("divided by 0"))
      expect(event).to be_a(Sentry::Event)
      expect(subject.send(:get_message_from_exception, event.to_hash)).to eq("ZeroDivisionError: divided by 0")
    end

    it_behaves_like "options"

    describe "options - message" do
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

    context 'for a nested exception type' do
      module Sentry::Test
        class Exception < RuntimeError; end
      end
      let(:exception) { Sentry::Test::Exception.new(message) }

      it 'sends the module name as part of the exception info' do
        expect(hash[:exception][:values][0][:module]).to eq('Sentry::Test')
      end
    end

    describe "exception types test" do
      context 'for a Sentry::Error' do
        let(:exception) { Sentry::Error.new }
        it 'does not create an event' do
          expect(subject.event_from_exception(exception)).to be_nil
        end
      end

      context 'for an excluded exception type' do
        module Sentry::Test
          class BaseExc < RuntimeError; end
          class SubExc < BaseExc; end
          module ExcTag; end
        end

        let(:config) { subject.configuration }

        context "invalid exclusion type" do
          it 'returns Sentry::Event' do
            config.excluded_exceptions << nil
            config.excluded_exceptions << 1
            config.excluded_exceptions << {}
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_a(Sentry::Event)
          end
        end

        context "defined by string type" do
          it 'returns nil for a class match' do
            config.excluded_exceptions << 'Sentry::Test::BaseExc'
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_nil
          end

          it 'returns nil for a top class match' do
            config.excluded_exceptions << '::Sentry::Test::BaseExc'
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_nil
          end

          it 'returns nil for a sub class match' do
            config.excluded_exceptions << 'Sentry::Test::BaseExc'
            expect(subject.event_from_exception(Sentry::Test::SubExc.new)).to be_nil
          end

          it 'returns nil for a tagged class match' do
            config.excluded_exceptions << 'Sentry::Test::ExcTag'
            expect(
              subject.event_from_exception(Sentry::Test::SubExc.new.tap { |x| x.extend(Sentry::Test::ExcTag) })
            ).to be_nil
          end

          it 'returns Sentry::Event for an undefined exception class' do
            config.excluded_exceptions << 'Sentry::Test::NonExistentExc'
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_a(Sentry::Event)
          end
        end

        context "defined by class type" do
          it 'returns nil for a class match' do
            config.excluded_exceptions << Sentry::Test::BaseExc
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_nil
          end

          it 'returns nil for a sub class match' do
            config.excluded_exceptions << Sentry::Test::BaseExc
            expect(subject.event_from_exception(Sentry::Test::SubExc.new)).to be_nil
          end

          it 'returns nil for a tagged class match' do
            config.excluded_exceptions << Sentry::Test::ExcTag
            expect(subject.event_from_exception(Sentry::Test::SubExc.new.tap { |x| x.extend(Sentry::Test::ExcTag) })).to be_nil
          end
        end
      end

      # Only check causes when they're supported
      if Exception.new.respond_to? :cause
        context 'when the exception has a cause' do
          let(:exception) { build_exception_with_cause }

          it 'captures the cause' do
            expect(hash[:exception][:values].length).to eq(2)
          end
        end

        context 'when the exception has nested causes' do
          let(:exception) { build_exception_with_two_causes }

          it 'captures nested causes' do
            expect(hash[:exception][:values].length).to eq(3)
          end
        end
      end

      context 'when the exception has a recursive cause' do
        let(:exception) { build_exception_with_recursive_cause }

        it 'should handle it gracefully' do
          expect(hash[:exception][:values].length).to eq(1)
        end
      end

      if RUBY_PLATFORM == "java"
        context 'when running under jRuby' do
          let(:exception) do
            begin
              raise java.lang.OutOfMemoryError, "A Java error"
            rescue Exception => e
              return e
            end
          end

          it 'should have a backtrace' do
            frames = hash[:exception][:values][0][:stacktrace][:frames]
            expect(frames.length).not_to eq(0)
          end
        end
      end

      context 'when the exception has a backtrace' do
        let(:exception) do
          e = Exception.new(message)
          allow(e).to receive(:backtrace).and_return [
            "/path/to/some/file:22:in `function_name'",
            "/some/other/path:1412:in `other_function'"
          ]
          e
        end

        it 'parses the backtrace' do
          frames = hash[:exception][:values][0][:stacktrace][:frames]
          expect(frames.length).to eq(2)
          expect(frames[0][:lineno]).to eq(1412)
          expect(frames[0][:function]).to eq('other_function')
          expect(frames[0][:filename]).to eq('/some/other/path')

          expect(frames[1][:lineno]).to eq(22)
          expect(frames[1][:function]).to eq('function_name')
          expect(frames[1][:filename]).to eq('/path/to/some/file')
        end

        context 'with internal backtrace' do
          let(:exception) do
            e = Exception.new(message)
            allow(e).to receive(:backtrace).and_return(["<internal:prelude>:10:in `synchronize'"])
            e
          end

          it 'marks filename and in_app correctly' do
            frames = hash[:exception][:values][0][:stacktrace][:frames]
            expect(frames[0][:lineno]).to eq(10)
            expect(frames[0][:function]).to eq("synchronize")
            expect(frames[0][:filename]).to eq("<internal:prelude>")
          end
        end

        context 'when a path in the stack trace is on the load path' do
          before do
            $LOAD_PATH << '/some'
          end

          after do
            $LOAD_PATH.delete('/some')
          end

          it 'strips prefixes in the load path from frame filenames' do
            frames = hash[:exception][:values][0][:stacktrace][:frames]
            expect(frames[0][:filename]).to eq('other/path')
          end
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
end
