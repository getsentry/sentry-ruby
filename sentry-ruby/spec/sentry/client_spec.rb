# frozen_string_literal: true

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
      config.dsn = Sentry::TestHelper::DUMMY_DSN
      config.transport.transport_class = Sentry::DummyTransport
    end
  end
  subject { Sentry::Client.new(configuration) }

  let(:transaction) do
    hub = Sentry::Hub.new(subject, Sentry::Scope.new)
    Sentry::Transaction.new(
      name: "test transaction",
      hub: hub,
      sampled: true
    )
  end

  let(:fake_time) { Time.now }

  before do
    allow(Time).to receive(:now).and_return fake_time
  end

  describe "#transport" do
    let(:configuration) { Sentry::Configuration.new }

    context "when transport.transport_class is provided" do
      before do
        configuration.dsn = Sentry::TestHelper::DUMMY_DSN
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
          configuration.dsn = Sentry::TestHelper::DUMMY_DSN
        end

        it "returns HTTP transport object" do
          expect(subject.transport).to be_a(Sentry::HTTPTransport)
        end
      end
    end
  end

  describe "#spotlight_transport" do
    it "nil by default" do
      expect(subject.spotlight_transport).to eq(nil)
    end

    it "nil when false" do
      configuration.spotlight = false
      expect(subject.spotlight_transport).to eq(nil)
    end

    it "has a transport when true" do
      configuration.spotlight = true
      expect(described_class.new(configuration).spotlight_transport).to be_a(Sentry::SpotlightTransport)
    end
  end

  describe "#send_event" do
    context "with spotlight enabled" do
      before { configuration.spotlight = true }

      it "calls spotlight transport" do
        event = subject.event_from_message('test')
        expect(subject.spotlight_transport).to receive(:send_event).with(event)
        subject.send_event(event)
      end
    end
  end

  describe '#send_envelope' do
    let(:envelope) do
      envelope = Sentry::Envelope.new({ env_header: 1 })
      envelope.add_item({ type: 'event' }, { payload: 'test' })
      envelope.add_item({ type: 'statsd' }, { payload: 'test2' })
      envelope.add_item({ type: 'transaction' }, { payload: 'test3' })
      envelope
    end

    it 'does not send envelope to either transport if disabled' do
      configuration.dsn = nil

      expect(subject.spotlight_transport).not_to receive(:send_envelope)
      expect(subject.transport).not_to receive(:send_envelope)
      subject.send_envelope(envelope)
    end

    it 'sends envelope to main transport if enabled' do
      expect(subject.transport).to receive(:send_envelope).with(envelope)
      subject.send_envelope(envelope)
    end

    it 'sends envelope with spotlight transport if enabled' do
      configuration.spotlight = true

      expect(subject.spotlight_transport).to receive(:send_envelope).with(envelope)
      subject.send_envelope(envelope)
    end

    context 'when transport failure' do
      let(:string_io) { StringIO.new }

      before do
        configuration.debug = true
        configuration.logger = ::Logger.new(string_io)

        allow(subject.transport).to receive(:send_envelope).and_raise(Sentry::ExternalError.new("networking error"))
      end

      it 'logs error' do
        expect do
          subject.send_envelope(envelope)
        end.to raise_error(Sentry::ExternalError)

        expect(string_io.string).to match(/Envelope sending failed: networking error/)
        expect(string_io.string).to match(__FILE__)
      end

      it 'records client reports for network errors' do
        expect do
          subject.send_envelope(envelope)
        end.to raise_error(Sentry::ExternalError)

        expect(subject.transport).to have_recorded_lost_event(:network_error, 'error')
        expect(subject.transport).to have_recorded_lost_event(:network_error, 'metric_bucket')
        expect(subject.transport).to have_recorded_lost_event(:network_error, 'transaction')
      end
    end
  end

  describe '#capture_envelope' do
    let(:envelope) do
      envelope = Sentry::Envelope.new({ env_header: 1 })
      envelope.add_item({ item_header: 42 }, { payload: 'test' })
      envelope
    end

    before do
      configuration.background_worker_threads = 0
      Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
    end

    it 'queues envelope to background worker' do
      expect(Sentry.background_worker).to receive(:perform).and_call_original
      expect(subject).to receive(:send_envelope).with(envelope)
      subject.capture_envelope(envelope)
    end
  end

  describe '#event_from_message' do
    let(:message) { 'This is a message' }

    it 'returns an event' do
      event = subject.event_from_message(message)
      hash = event.to_hash

      expect(event).to be_a(Sentry::ErrorEvent)
      expect(hash[:message]).to eq(message)
      expect(hash[:level]).to eq(:error)
    end

    it "inserts threads interface to the event" do
      event = nil

      t = Thread.new do
        event = subject.event_from_message(message)
      end

      t.name = "Thread 1"
      t.join
      hash = event.to_hash

      thread = hash[:threads][:values][0]
      expect(thread[:id]).to eq(t.object_id)
      expect(thread[:name]).to eq("Thread 1")
      expect(thread[:crashed]).to eq(false)
      expect(thread[:stacktrace]).not_to be_empty
    end
  end

  describe "#event_from_transaction" do
    let(:hub) do
      Sentry::Hub.new(subject, Sentry::Scope.new)
    end

    let(:transaction) do
      hub.start_transaction(name: "test transaction")
    end

    before do
      configuration.traces_sample_rate = 1.0

      transaction.start_child(op: "unfinished child")
      transaction.start_child(op: "finished child", timestamp: Time.now.utc.iso8601)
    end

    it "initializes a correct event for the transaction" do
      event = subject.event_from_transaction(transaction)
      event_hash = event.to_hash

      expect(event_hash[:type]).to eq("transaction")
      expect(event_hash[:contexts][:trace]).to eq(transaction.get_trace_context)
      expect(event_hash[:timestamp]).to eq(transaction.timestamp)
      expect(event_hash[:start_timestamp]).to eq(transaction.start_timestamp)
      expect(event_hash[:transaction]).to eq("test transaction")
      expect(event_hash[:spans].count).to eq(1)
      expect(event_hash[:spans][0][:op]).to eq("finished child")
      expect(event_hash[:level]).to eq(nil)
    end

    it "correct dynamic_sampling_context when incoming baggage header" do
      baggage = Sentry::Baggage.from_incoming_header(
        "other-vendor-value-1=foo;bar;baz, "\
        "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
        "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
        "sentry-sample_rate=0.01337, "\
        "sentry-user_id=Am%C3%A9lie,  "\
        "other-vendor-value-2=foo;bar;"
      )

      transaction = Sentry::Transaction.new(name: "test transaction", hub: hub, baggage: baggage, sampled: true)
      event = subject.event_from_transaction(transaction)

      expect(event.dynamic_sampling_context).to eq({
        "sample_rate" => "0.01337",
        "public_key" => "49d0f7386ad645858ae85020e393bef3",
        "trace_id" => "771a43a4192642f0b136d5159a501700",
        "user_id" => "Amélie"
      })
    end

    it "correct dynamic_sampling_context when head SDK" do
      event = subject.event_from_transaction(transaction)

      expect(event.dynamic_sampling_context).to eq({
        "environment" => "development",
        "public_key" => "12345",
        "sample_rate" => "1.0",
        "sampled" => "true",
        "transaction" => "test transaction",
        "trace_id" => transaction.trace_id
      })
    end

    it "adds explicitly added contexts to event" do
      transaction.set_context(:foo, { bar: 42 })
      event = subject.event_from_transaction(transaction)
      expect(event.contexts).to include({ foo: { bar: 42 } })
    end

    it 'adds metric summary on transaction if any' do
      key = [:c, 'incr', 'none', []]
      transaction.metrics_local_aggregator.add(key, 10)
      hash = subject.event_from_transaction(transaction).to_hash

      expect(hash[:_metrics_summary]).to eq({
        'c:incr@none' => { count: 1, max: 10.0, min: 10.0, sum: 10.0, tags: {} }
      })
    end
  end

  describe "#event_from_exception" do
    let(:message) { 'This is a message' }
    let(:exception) { Exception.new(message) }
    let(:event) { subject.event_from_exception(exception) }
    let(:hash) { event.to_hash }

    it "sets the message to the exception's value and type" do
      expect(hash[:exception][:values][0][:type]).to eq("Exception")
      expect(hash[:exception][:values][0][:value]).to match(message)
    end

    context "with special error messages" do
      let(:exception) do
        begin
          {}[:foo][:bar]
        rescue => e
          e
        end
      end

      it "sets correct exception message based on Ruby version" do
        version = Gem::Version.new(RUBY_VERSION)

        case
        when version >= Gem::Version.new("3.4.0-dev")
          expect(hash[:exception][:values][0][:value]).to eq(
            "undefined method '[]' for nil (NoMethodError)\n\n          {}[:foo][:bar]\n                  ^^^^^^"
          )
        when version >= Gem::Version.new("3.3.0-dev")
          expect(hash[:exception][:values][0][:value]).to eq(
            "undefined method `[]' for nil (NoMethodError)\n\n          {}[:foo][:bar]\n                  ^^^^^^"
          )
        when version >= Gem::Version.new("3.2")
          expect(hash[:exception][:values][0][:value]).to eq(
            "undefined method `[]' for nil:NilClass (NoMethodError)\n\n          {}[:foo][:bar]\n                  ^^^^^^"
          )
        when version >= Gem::Version.new("3.1") && RUBY_ENGINE == "ruby"
          expect(hash[:exception][:values][0][:value]).to eq(
            "undefined method `[]' for nil:NilClass\n\n          {}[:foo][:bar]\n                  ^^^^^^"
          )
        else
          expect(hash[:exception][:values][0][:value]).to eq("undefined method `[]' for nil:NilClass")
        end
      end

      it "converts non-string error message" do
        NonStringMessageError = Class.new(StandardError) do
          def detailed_message(*)
            { foo: "bar" }
          end
        end

        event = subject.event_from_exception(NonStringMessageError.new)
        hash = event.to_hash
        expect(event).to be_a(Sentry::ErrorEvent)

        if RUBY_VERSION >= "3.4"
          expect(hash[:exception][:values][0][:value]).to eq("{foo: \"bar\"}")
        else
          expect(hash[:exception][:values][0][:value]).to eq("{:foo=>\"bar\"}")
        end
      end
    end

    it "sets threads interface without stacktrace" do
      event = nil

      t = Thread.new do
        event = subject.event_from_exception(exception)
      end

      t.name = "Thread 1"
      t.join

      event_hash = event.to_hash
      thread = event_hash[:threads][:values][0]

      expect(thread[:id]).to eq(t.object_id)
      expect(event_hash.dig(:exception, :values, 0, :thread_id)).to eq(t.object_id)
      expect(thread[:name]).to eq("Thread 1")
      expect(thread[:crashed]).to eq(true)
      expect(thread[:stacktrace]).to be_nil
    end

    it 'has level ERROR' do
      expect(hash[:level]).to eq(:error)
    end

    it 'does not belong to a module' do
      expect(hash[:exception][:values][0][:module]).to eq('')
    end

    it 'returns an event' do
      event = subject.event_from_exception(ZeroDivisionError.new("divided by 0"))
      expect(event).to be_a(Sentry::ErrorEvent)
      hash = event.to_hash
      expect(hash[:exception][:values][0][:type]).to match("ZeroDivisionError")
      expect(hash[:exception][:values][0][:value]).to match("divided by 0")
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

      context 'for a Sentry::ExternalError' do
        let(:exception) { Sentry::ExternalError.new }
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
          it 'returns Sentry::ErrorEvent' do
            config.excluded_exceptions << nil
            config.excluded_exceptions << 1
            config.excluded_exceptions << {}
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_a(Sentry::ErrorEvent)
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

          it 'returns Sentry::ErrorEvent for an undefined exception class' do
            config.excluded_exceptions << 'Sentry::Test::NonExistentExc'
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new)).to be_a(Sentry::ErrorEvent)
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

        context "when exclusions overridden with :ignore_exclusions" do
          it 'returns Sentry::ErrorEvent' do
            config.excluded_exceptions << Sentry::Test::BaseExc
            expect(subject.event_from_exception(Sentry::Test::BaseExc.new, { ignore_exclusions: true })).to be_a(Sentry::ErrorEvent)
          end
        end
      end

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

    describe "bad encoding character handling" do
      context "if exception message contains illegal/malformed encoding characters" do
        let(:exception) do
          begin
            raise "#{message}\x1F\xE6"
          rescue => e
            e
          end
        end

        it "scrub bad encoding error message" do
          expect { event.to_json_compatible }.not_to raise_error
          version = Gem::Version.new(RUBY_VERSION)
          if version >= Gem::Version.new("3.2")
            expect(hash[:exception][:values][0][:value]).to eq("#{message}\x1F\uFFFD (RuntimeError)")
          else
            expect(hash[:exception][:values][0][:value]).to eq("#{message}\x1F\uFFFD")
          end
        end
      end

      context "if local variable contains illegal/malformed encoding characters" do
        before do
          perform_basic_setup do |config|
            config.include_local_variables = true
          end
        end

        after do
          Sentry.exception_locals_tp.disable
        end

        let(:exception) do
          begin
            long = "*" * 1022 + "\x1F\xE6" + "*" * 1000
            foo = "local variable \x1F\xE6"
            raise message
          rescue => e
            e
          end
        end

        it "scrub bad encoding characters" do
          expect { event.to_json_compatible }.not_to raise_error
          version = Gem::Version.new(RUBY_VERSION)
          if version >= Gem::Version.new("3.2")
            expect(hash[:exception][:values][0][:value]).to eq("#{message} (RuntimeError)")
            frames = hash[:exception][:values][0][:stacktrace][:frames]
            expect(frames[-1][:vars][:long]).to eq("*" * 1022 + "\x1F\uFFFD" + "...")
            expect(frames[-1][:vars][:foo]).to eq "local variable \x1F\uFFFD"
          else
            expect(hash[:exception][:values][0][:value]).to eq(message)
            frames = hash[:exception][:values][0][:stacktrace][:frames]
            expect(frames[-1][:vars][:long]).to eq("*" * 1022 + "\x1F\uFFFD" + "...")
            expect(frames[-1][:vars][:foo]).to eq "local variable \x1F\uFFFD"
          end
        end
      end
    end

    describe 'mechanism' do
      it 'has type generic and handled true by default' do
        mechanism = hash[:exception][:values][0][:mechanism]
        expect(mechanism).to eq({ type: 'generic', handled: true })
      end

      it 'has correct custom mechanism when passed' do
        mech = Sentry::Mechanism.new(type: 'custom', handled: false)
        event = subject.event_from_exception(exception, mechanism: mech)
        hash = event.to_hash
        mechanism = hash[:exception][:values][0][:mechanism]
        expect(mechanism).to eq({ type: 'custom', handled: false })
      end
    end
  end

  describe "#event_from_check_in" do
    let(:slug) { "test_slug" }
    let(:status) { :ok }

    it 'returns an event' do
      event = subject.event_from_check_in(slug, status)
      expect(event).to be_a(Sentry::CheckInEvent)

      hash = event.to_hash
      expect(hash[:monitor_slug]).to eq(slug)
      expect(hash[:status]).to eq(status)
      expect(hash[:check_in_id].length).to eq(32)
    end

    it 'returns an event with correct optional attributes from crontab config' do
      event = subject.event_from_check_in(
        slug,
        status,
        duration: 30,
        check_in_id: "xxx-yyy",
        monitor_config: Sentry::Cron::MonitorConfig.from_crontab("* * * * *")
      )

      expect(event).to be_a(Sentry::CheckInEvent)

      hash = event.to_hash
      expect(hash[:monitor_slug]).to eq(slug)
      expect(hash[:status]).to eq(status)
      expect(hash[:check_in_id]).to eq("xxx-yyy")
      expect(hash[:duration]).to eq(30)
      expect(hash[:monitor_config]).to eq({ schedule: { type: :crontab, value: "* * * * *" } })
    end

    it 'returns an event with correct optional attributes from interval config' do
      event = subject.event_from_check_in(
        slug,
        status,
        duration: 30,
        check_in_id: "xxx-yyy",
        monitor_config: Sentry::Cron::MonitorConfig.from_interval(30, :minute)
      )

      expect(event).to be_a(Sentry::CheckInEvent)

      hash = event.to_hash
      expect(hash[:monitor_slug]).to eq(slug)
      expect(hash[:status]).to eq(status)
      expect(hash[:check_in_id]).to eq("xxx-yyy")
      expect(hash[:duration]).to eq(30)
      expect(hash[:monitor_config]).to eq({ schedule: { type: :interval, value: 30, unit: :minute } })
    end
  end

  describe "#generate_sentry_trace" do
    let(:string_io) { StringIO.new }
    let(:logger) do
      ::Logger.new(string_io)
    end

    before do
      configuration.logger = logger
    end

    let(:span) { Sentry::Span.new(transaction: transaction) }

    it "generates the trace with given span and logs correct message" do
      expect(subject.generate_sentry_trace(span)).to eq(span.to_sentry_trace)
      expect(string_io.string).to match(
        /\[Tracing\] Adding sentry-trace header to outgoing request: #{span.to_sentry_trace}/
      )
    end

    context "with config.propagate_traces = false" do
      before do
        configuration.propagate_traces = false
      end

      it "returns nil" do
        expect(subject.generate_sentry_trace(span)).to eq(nil)
      end
    end
  end

  describe "#generate_baggage" do
    before { configuration.logger = logger }

    let(:string_io) { StringIO.new }
    let(:logger) { ::Logger.new(string_io) }
    let(:baggage) do
      Sentry::Baggage.from_incoming_header(
        "other-vendor-value-1=foo;bar;baz, sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
        "sentry-public_key=49d0f7386ad645858ae85020e393bef3, sentry-sample_rate=0.01337, "\
        "sentry-user_id=Am%C3%A9lie, other-vendor-value-2=foo;bar;"
      )
    end

    let(:span) do
      hub = Sentry::Hub.new(subject, Sentry::Scope.new)
      transaction = Sentry::Transaction.new(name: "test transaction",
                                            baggage: baggage,
                                            hub: hub,
                                            sampled: true)

      transaction.start_child(op: "finished child", timestamp: Time.now.utc.iso8601)
    end

    it "generates the baggage header with given span and logs correct message" do
      generated_baggage = subject.generate_baggage(span)
      expect(generated_baggage).to eq(span.to_baggage)

      expect(generated_baggage).to eq(
        "sentry-trace_id=771a43a4192642f0b136d5159a501700,"\
        "sentry-public_key=49d0f7386ad645858ae85020e393bef3,"\
        "sentry-sample_rate=0.01337,"\
        "sentry-user_id=Am%C3%A9lie"
      )

      expect(string_io.string).to match(
        /\[Tracing\] Adding baggage header to outgoing request: #{span.to_baggage}/
      )
    end

    context "with config.propagate_traces = false" do
      before do
        configuration.propagate_traces = false
      end

      it "returns nil" do
        expect(subject.generate_baggage(span)).to eq(nil)
      end
    end
  end
end
