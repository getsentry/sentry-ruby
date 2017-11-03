require 'spec_helper'

RSpec.describe Raven::Instance do
  let(:event) { Raven::Event.new(:event_id => "event_id") }
  let(:options) { { :key => "value" } }
  let(:context) { nil }
  let(:configuration) do
    config = Raven::Configuration.new
    config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
    config.logger = Logger.new(nil)
    config
  end

  subject { described_class.new(context, configuration) }

  before do
    allow(subject).to receive(:send_event)
    allow(Raven::Event).to receive(:from_message) { event }
    allow(Raven::Event).to receive(:from_exception) { event }
  end

  describe '#context' do
    it 'is Raven.context by default' do
      expect(subject.context).to equal(Raven.context)
    end

    context 'initialized with a context' do
      let(:context) { :explicit }

      it 'is not Raven.context' do
        expect(subject.context).to_not equal(Raven.context)
      end
    end
  end

  describe '#capture_type' do
    describe 'as #capture_message' do
      before do
        expect(Raven::Event).to receive(:from_message).with(message, options)
        expect(subject).to receive(:send_event).with(event)
      end
      let(:message) { "Test message" }

      it 'sends the result of Event.from_message' do
        subject.capture_type(message, options)
      end

      it 'yields the event to a passed block' do
        expect { |b| subject.capture_type(message, options, &b) }.to yield_with_args(event)
      end
    end

    describe 'as #capture_message when async' do
      let(:message) { "Test message" }

      around do |example|
        prior_async = subject.configuration.async
        subject.configuration.async = proc { :ok }
        example.run
        subject.configuration.async = prior_async
      end

      it 'sends the result of Event.capture_type' do
        expect(Raven::Event).to receive(:from_message).with(message, options)
        expect(subject).not_to receive(:send_event).with(event)

        expect(subject.configuration.async).to receive(:call).with(event.to_json_compatible)
        subject.capture_message(message, options)
      end

      it 'returns the generated event' do
        returned = subject.capture_message(message, options)
        expect(returned).to eq(event)
      end
    end

    describe 'as #capture_exception' do
      let(:exception) { build_exception }

      it 'sends the result of Event.from_exception' do
        expect(Raven::Event).to receive(:from_exception).with(exception, options)
        expect(subject).to receive(:send_event).with(event)

        subject.capture_exception(exception, options)
      end

      it 'has an alias' do
        expect(Raven::Event).to receive(:from_exception).with(exception, options)
        expect(subject).to receive(:send_event).with(event)

        subject.capture_exception(exception, options)
      end
    end

    describe 'as #capture_exception when async' do
      let(:exception) { build_exception }

      context "when async" do
        around do |example|
          prior_async = subject.configuration.async
          subject.configuration.async = proc { :ok }
          example.run
          subject.configuration.async = prior_async
        end

        it 'sends the result of Event.from_exception' do
          expect(Raven::Event).to receive(:from_exception).with(exception, options)
          expect(subject).not_to receive(:send_event).with(event)

          expect(subject.configuration.async).to receive(:call).with(event.to_json_compatible)
          subject.capture_exception(exception, options)
        end

        it 'returns the generated event' do
          returned = subject.capture_exception(exception, options)
          expect(returned).to eq(event)
        end
      end

      context "when async raises an exception" do
        around do |example|
          prior_async = subject.configuration.async
          subject.configuration.async = proc { raise TypeError }
          example.run
          subject.configuration.async = prior_async
        end

        it 'sends the result of Event.from_exception via fallback' do
          expect(Raven::Event).to receive(:from_exception).with(exception, options)

          expect(subject.configuration.async).to receive(:call).with(event.to_json_compatible)
          subject.capture_exception(exception, options)
        end
      end
    end

    describe 'as #capture_exception with a should_capture callback' do
      let(:exception) { build_exception }

      it 'sends the result of Event.from_exception according to the result of should_capture' do
        expect(subject).not_to receive(:send_event).with(event)

        subject.configuration.should_capture = proc { false }
        expect(subject.configuration.should_capture).to receive(:call).with(exception)
        expect(subject.capture_exception(exception, options)).to be false
      end
    end
  end

  describe '#capture' do
    context 'given a block' do
      it 'yields to the given block' do
        expect { |b| subject.capture(&b) }.to yield_with_no_args
      end
    end

    it 'does not install an at_exit hook' do
      expect(Kernel).not_to receive(:at_exit)
      subject.capture {}
    end
  end

  describe '#report_status' do
    let(:ready_message) do
      "Raven #{Raven::VERSION} ready to catch errors"
    end

    let(:not_ready_message) do
      "Raven #{Raven::VERSION} configured not to capture errors."
    end

    it 'logs a ready message when configured' do
      subject.configuration.silence_ready = false

      expect(subject.logger).to receive(:info).with(ready_message)
      subject.report_status
    end

    it 'logs not ready message if the config does not send in current environment' do
      subject.configuration.silence_ready = false
      subject.configuration.environments = ["production"]
      expect(subject.logger).to receive(:info).with(
        "Raven #{Raven::VERSION} configured not to capture errors: Not configured to send/capture in environment 'default'"
      )
      subject.report_status
    end

    it 'logs nothing if "silence_ready" configuration is true' do
      subject.configuration.silence_ready = true
      expect(subject.logger).not_to receive(:info)
      subject.report_status
    end
  end

  describe '.last_event_id' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_type' do
      expect(subject).to receive(:send_event).with(event)

      subject.capture_type("Test message", options)

      expect(subject.last_event_id).to eq(event.event_id)
    end
  end

  describe "#rack_context" do
    it "doesn't set anything if the context is empty" do
      subject.rack_context({})
      expect(subject.context.rack_env).to eq({})
    end

    it "sets arbitrary rack context" do
      subject.rack_context(:foo => :bar)
      expect(subject.context.rack_env[:foo]).to eq(:bar)
    end
  end
end
