require 'spec_helper'

class ExceptionWithContext < StandardError
  def sentry_context
    {
      foo: "bar"
    }
  end
end

RSpec.describe Sentry::Client do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = DUMMY_DSN
    end
  end
  subject { Sentry::Client.new(configuration) }

  let(:fake_time) { Time.now }

  before do
    allow(Time).to receive(:now).and_return fake_time
  end

  describe "#capture_event" do
    context 'async' do
      let(:message) { "Test message" }
      let(:scope) { Sentry::Scope.new }
      let(:event) { subject.event_from_message(message) }

      around do |example|
        prior_async = configuration.async
        configuration.async = proc { :ok }
        example.run
        configuration.async = prior_async
      end

      before do
        allow(subject).to receive(:send_data)
      end

      it "doesn't send the event right away" do
        expect(configuration.async).to receive(:call)

        returned = subject.capture_event(event, scope)

        expect(returned).to be_a(Sentry::Event)
      end

      context "when async raises an exception" do
        around do |example|
          prior_async = configuration.async
          configuration.async = proc { raise TypeError }
          example.run
          configuration.async = prior_async
        end

        it 'sends the result of Event.capture_exception via fallback' do
          expect(configuration.logger).to receive(:error).with(Sentry::LOGGER_PROGNAME) { "async event sending failed: TypeError" }
          expect(configuration.async).to receive(:call).and_call_original
          expect(subject).to receive(:send_event)

          subject.capture_event(event, scope)
        end
      end
    end

  end

  describe "#send_event" do
    let(:event) { subject.event_from_exception(ZeroDivisionError.new("divided by 0")) }

    before do
      allow(subject.transport).to receive(:send_data)
    end

    it "sends data through the transport" do
      expect(subject.transport).to receive(:send_event).with(event)

      subject.send_event(event)
    end

    it "applies before_send callback before sending the event" do
      configuration.before_send = lambda do |event|
        event.tags[:called] = true
        event
      end

      e = subject.send_event(event)

      expect(e.tags[:called]).to eq(true)
    end
  end

  describe "#transport" do
    context "when transport.transport_class is provided" do
      before do
        configuration.dsn = DUMMY_DSN
        configuration.transport.transport_class = Sentry::DummyTransport
      end

      it "uses that class regardless if dsn is set" do
        expect(subject.transport).to be_a(Sentry::DummyTransport)
      end
    end

    context "when transport.transport_class is not provided" do
      context "when dsn is not set" do
        subject { described_class.new(Sentry::Configuration.new) }

        it "returns dummy transport object" do
          expect(subject.transport).to be_a(Sentry::DummyTransport)
        end
      end

      context "when dsn is set" do
        before do
          configuration.dsn = DUMMY_DSN
        end

        it "returns HTTP transport object" do
          expect(subject.transport).to be_a(Sentry::HTTPTransport)
        end
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
  end

  describe "#event_from_transaction" do
    let(:hub) do
      Sentry::Hub.new(subject, Sentry::Scope.new)
    end
    let(:transaction) do
      Sentry::Transaction.new(name: "test transaction", sampled: true)
    end

    before do
      transaction.start_child(op: "unfinished child")
      transaction.start_child(op: "finished child", timestamp: Time.now.utc.iso8601)
    end

    it "initializes a correct event for the transaction" do
      event = subject.event_from_transaction(transaction).to_hash

      expect(event[:type]).to eq("transaction")
      expect(event[:contexts][:trace]).to eq(transaction.get_trace_context)
      expect(event[:timestamp]).to eq(transaction.timestamp)
      expect(event[:start_timestamp]).to eq(transaction.start_timestamp)
      expect(event[:transaction]).to eq("test transaction")
      expect(event[:spans].count).to eq(1)
      expect(event[:spans][0][:op]).to eq("finished child")
    end
  end

  describe "#event_from_exception" do
    let(:message) { 'This is a message' }
    let(:exception) { Exception.new(message) }
    let(:event) { subject.event_from_exception(exception) }
    let(:hash) { event.to_hash }

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
      expect(Sentry::Event.get_message_from_exception(event.to_hash)).to eq("ZeroDivisionError: divided by 0")
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

      context 'when the exception responds to sentry_context' do
        let(:hash) do
          event = subject.event_from_exception(ExceptionWithContext.new)
          event.to_hash
        end

        it "merges the context into event's extra" do
          expect(hash[:extra][:foo]).to eq('bar')
        end
      end
    end
  end
end
