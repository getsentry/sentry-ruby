require 'spec_helper'
require 'raven/instance'

RSpec.describe Raven::Instance do
  let(:event) { Raven::Event.new(id: "event_id", configuration: configuration, context: Raven.context, breadcrumbs: Raven.breadcrumbs) }
  let(:options) { { :key => "value" } }
  let(:event_options) { options.merge(:context => subject.context, :configuration => configuration, breadcrumbs: Raven.breadcrumbs) }
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
        expect(Raven::Event).to receive(:from_message).with(message, event_options)
        expect(subject).to receive(:send_event).with(event, :exception => nil, :message => message)
      end
      let(:message) { "Test message" }

      it 'sends the result of Event.capture_message' do
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
        expect(Raven::Event).to receive(:from_message).with(message, event_options)
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

      it 'sends the result of Event.capture_exception' do
        expect(Raven::Event).to receive(:from_exception).with(exception, event_options)
        expect(subject).to receive(:send_event).with(event, :exception => exception, :message => nil)

        subject.capture_exception(exception, options)
      end

      it 'has an alias' do
        expect(Raven::Event).to receive(:from_exception).with(exception, event_options)
        expect(subject).to receive(:send_event).with(event, :exception => exception, :message => nil)

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

        it 'sends the result of Event.capture_exception' do
          expect(Raven::Event).to receive(:from_exception).with(exception, event_options)
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

        it 'sends the result of Event.capture_exception via fallback' do
          expect(Raven::Event).to receive(:from_exception).with(exception, event_options)

          expect(subject.configuration.async).to receive(:call).with(event.to_json_compatible)
          subject.capture_exception(exception, options)
        end
      end
    end

    describe 'as #capture_exception with a should_capture callback' do
      let(:exception) { build_exception }

      it 'sends the result of Event.capture_exception according to the result of should_capture' do
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

  describe '#annotate_exception' do
    let(:exception) { build_exception }

    def ivars(object)
      object.instance_variables.map(&:to_s)
    end

    it 'adds an annotation to the exception' do
      expect(ivars(exception)).not_to include("@__raven_context")
      subject.annotate_exception(exception, {})
      expect(ivars(exception)).to include("@__raven_context")
      expect(exception.instance_variable_get(:@__raven_context)).to \
        be_kind_of Hash
    end

    context 'when the exception already has context' do
      it 'does a deep merge of options' do
        subject.annotate_exception(exception, :extra => { :language => "ruby" })
        subject.annotate_exception(exception, :extra => { :job_title => "engineer" })
        expected_hash = { :extra => { :language => "ruby", :job_title => "engineer" } }
        expect(exception.instance_variable_get(:@__raven_context)).to \
          eq expected_hash
      end
    end
  end

  describe '#report_status' do
    let(:ready_message) do
      "Raven #{Raven::VERSION} ready to catch errors"
    end

    let(:not_ready_message) do
      "Raven #{Raven::VERSION} configured not to capture errors: DSN not set"
    end

    context "when current environment is included in environments" do
      before do
        subject.configuration.silence_ready = false
        subject.configuration.environments = ["default"]
      end

      it 'logs a ready message when configured' do
        expect(subject.logger).to receive(:info).with(ready_message)
        subject.report_status
      end

      it 'logs a warning message when not properly configured' do
        # dsn not set
        subject.configuration = Raven::Configuration.new

        expect(subject.logger).to receive(:info).with(not_ready_message)
        subject.report_status
      end

      it 'logs nothing if "silence_ready" configuration is true' do
        subject.configuration.silence_ready = true
        expect(subject.logger).not_to receive(:info)
        subject.report_status
      end
    end

    context "when current environment is not included in environments" do
      it "doesn't log any message" do
        subject.configuration.silence_ready = false
        subject.configuration.environments = ["production"]
        expect(subject.logger).not_to receive(:info)
        subject.report_status
      end
    end
  end

  describe '.last_event_id' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_type' do
      expect(subject).to receive(:send_event).with(event, :exception => nil, :message => message)

      subject.capture_type("Test message", options)

      expect(subject.last_event_id).to eq(event.id)
    end
  end

  describe "#user_context" do
    context "without a block" do
      it "empties the user context when called without options" do
        subject.context.user = { id: 1 }
        expect(subject.user_context).to eq({})
      end

      it "empties the user context when called with nil" do
        subject.context.user = { id: 1 }
        expect(subject.user_context(nil)).to eq({})
      end

      it "empties the user context when called with {}" do
        subject.context.user = { id: 1 }
        expect(subject.user_context({})).to eq({})
      end

      it "returns the user context when set" do
        expected = { id: 1 }
        expect(subject.user_context(expected)).to eq(expected)
      end
    end

    context "with a block" do
      it "returns the user context when set" do
        expected = { id: 1 }
        user_context = subject.user_context(expected) do
          # do nothing
        end
        expect(user_context).to eq expected
      end

      it "sets user context only in the block" do
        subject.context.user = previous_user_context = { id: 9999 }
        new_user_context = { id: 1 }

        subject.user_context(new_user_context) do
          expect(subject.context.user).to eq new_user_context
        end
        expect(subject.context.user).to eq previous_user_context
      end
    end
  end

  describe "#tags_context" do
    let(:default) { { :foo => :bar } }
    let(:additional) { { :baz => :qux } }

    before do
      subject.context.tags = default
    end

    it "returns the tags" do
      expect(subject.tags_context).to eq default
    end

    it "returns the tags" do
      expect(subject.tags_context(additional)).to eq default.merge(additional)
    end

    it "doesn't set anything if the tags is empty" do
      subject.tags_context({})
      expect(subject.context.tags).to eq default
    end

    it "adds tags" do
      subject.tags_context(additional)
      expect(subject.context.tags).to eq default.merge(additional)
    end

    context 'when block given' do
      it "returns the tags" do
        tags = subject.tags_context(additional) do
          # do nothing
        end
        expect(tags).to eq default
      end

      it "adds tags only in the block" do
        subject.tags_context(additional) do
          expect(subject.context.tags).to eq default.merge(additional)
        end
        expect(subject.context.tags).to eq default
      end
    end
  end

  describe "#extra_context" do
    let(:default) { { :foo => :bar } }
    let(:additional) { { :baz => :qux } }

    before do
      subject.context.extra = default
    end

    it "returns the extra" do
      expect(subject.extra_context).to eq default
    end

    it "returns the extra" do
      expect(subject.extra_context(additional)).to eq default.merge(additional)
    end

    it "doesn't set anything if the extra is empty" do
      subject.extra_context({})
      expect(subject.context.extra).to eq default
    end

    it "adds extra" do
      subject.extra_context(additional)
      expect(subject.context.extra).to eq default.merge(additional)
    end

    context 'when block given' do
      it "returns the extra" do
        extra = subject.extra_context(additional) do
          # do nothing
        end
        expect(extra).to eq default
      end

      it "adds extra only in the block" do
        subject.extra_context(additional) do
          expect(subject.context.extra).to eq default.merge(additional)
        end
        expect(subject.context.extra).to eq default
      end
    end
  end

  describe "#rack_context" do
    it "doesn't set anything if the context is empty" do
      subject.rack_context({})
      expect(subject.context.rack_env).to be_nil
    end

    it "sets arbitrary rack context" do
      subject.rack_context(:foo => :bar)
      expect(subject.context.rack_env[:foo]).to eq(:bar)
    end
  end
end
