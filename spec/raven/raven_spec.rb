require 'spec_helper'

describe Raven do
  let(:event) { double("event") }
  let(:options) { double("options") }

  before do
    allow(Raven).to receive(:send)
    allow(Raven::Event).to receive(:from_message) { event }
    allow(Raven::Event).to receive(:from_exception) { event }
  end

  describe '.capture_message' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_message' do
      expect(Raven::Event).to receive(:from_message).with(message, options)
      expect(Raven).to receive(:send).with(event)

      Raven.capture_message(message, options)
    end

    it 'yields the event to a passed block' do
      expect { |b| Raven.capture_message(message, options, &b) }.to yield_with_args(event)
    end
  end

  describe '.capture_message when async' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_message' do
      expect(Raven::Event).to receive(:from_message).with(message, options)
      expect(Raven).not_to receive(:send).with(event)

      prior_async = Raven.configuration.async
      Raven.configuration.async = lambda { |e| :ok }
      expect(Raven.configuration.async).to receive(:call).with(event)
      Raven.capture_message(message, options)
      Raven.configuration.async = prior_async
    end
  end

  describe '.capture_exception' do
    let(:exception) { build_exception }

    it 'sends the result of Event.capture_exception' do
      expect(Raven::Event).to receive(:from_exception).with(exception, options)
      expect(Raven).to receive(:send).with(event)

      Raven.capture_exception(exception, options)
    end

    it 'yields the event to a passed block' do
      expect { |b| Raven.capture_exception(exception, options, &b) }.to yield_with_args(event)
    end
  end

  describe '.capture_exception when async' do
    let(:exception) { build_exception }

    it 'sends the result of Event.capture_exception' do
      expect(Raven::Event).to receive(:from_exception).with(exception, options)
      expect(Raven).not_to receive(:send).with(event)

      prior_async = Raven.configuration.async
      Raven.configuration.async = lambda { |e| :ok }
      expect(Raven.configuration.async).to receive(:call).with(event)
      Raven.capture_exception(exception, options)
      Raven.configuration.async = prior_async
    end
  end

  describe '.capture_exception with a should_send callback' do
    let(:exception) { build_exception }

    it 'sends the result of Event.capture_exception according to the result of should_send' do
      expect(Raven).not_to receive(:send).with(event)

      prior_should_send = Raven.configuration.should_send
      Raven.configuration.should_send = Proc.new { |e| false }
      expect(Raven.configuration.should_send).to receive(:call).with(exception)
      Raven.capture_exception(exception, options)
      Raven.configuration.should_send = prior_should_send
    end
  end

  describe '.annotate_exception' do
    let(:exception) { build_exception }

    def ivars(object)
      object.instance_variables.map { |name| name.to_s }
    end

    it 'adds an annotation to the exception' do
      expect(ivars(exception)).not_to include("@__raven_context")
      Raven.annotate_exception(exception, {})
      expect(ivars(exception)).to include("@__raven_context")
      expect(exception.instance_variable_get(:@__raven_context)).to \
        be_kind_of Hash
    end
  end



end
