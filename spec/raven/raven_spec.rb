require 'spec_helper'

describe Raven do
  let(:event) { double("event") }
  let(:options) { double("options") }

  before do
    allow(Raven).to receive(:send_event)
    allow(Raven::Event).to receive(:from_message) { event }
    allow(Raven::Event).to receive(:from_exception) { event }
  end

  describe '.capture_message' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_message' do
      expect(Raven::Event).to receive(:from_message).with(message, options)
      expect(Raven).to receive(:send_event).with(event)

      Raven.capture_message(message, options)
    end

    it 'yields the event to a passed block' do
      expect { |b| Raven.capture_message(message, options, &b) }.to yield_with_args(event)
    end
  end

  describe '.capture_message when async' do
    let(:message) { "Test message" }

    around do |example|
      prior_async = Raven.configuration.async
      Raven.configuration.async = lambda { |event| :ok }
      example.run
      Raven.configuration.async = prior_async
    end

    it 'sends the result of Event.capture_message' do
      expect(Raven::Event).to receive(:from_message).with(message, options)
      expect(Raven).not_to receive(:send_event).with(event)

      expect(Raven.configuration.async).to receive(:call).with(event)
      Raven.capture_message(message, options)
    end

    it 'returns the generated event' do
      returned = Raven.capture_message(message, options)
      expect(returned).to eq(event)
    end
  end

  describe '.capture_exception' do
    let(:exception) { build_exception }

    it 'sends the result of Event.capture_exception' do
      expect(Raven::Event).to receive(:from_exception).with(exception, options)
      expect(Raven).to receive(:send_event).with(event)

      Raven.capture_exception(exception, options)
    end

    it 'yields the event to a passed block' do
      expect { |b| Raven.capture_exception(exception, options, &b) }.to yield_with_args(event)
    end
  end

  describe '.capture_exception when async' do
    let(:exception) { build_exception }

    around do |example|
      prior_async = Raven.configuration.async
      Raven.configuration.async = lambda { |event| :ok }
      example.run
      Raven.configuration.async = prior_async
    end

    it 'sends the result of Event.capture_exception' do
      expect(Raven::Event).to receive(:from_exception).with(exception, options)
      expect(Raven).not_to receive(:send_event).with(event)

      expect(Raven.configuration.async).to receive(:call).with(event)
      Raven.capture_exception(exception, options)
    end

    it 'returns the generated event' do
      returned = Raven.capture_exception(exception, options)
      expect(returned).to eq(event)
    end
  end

  describe '.capture_exception with a should_capture callback' do
    let(:exception) { build_exception }

    it 'sends the result of Event.capture_exception according to the result of should_capture' do
      expect(Raven).not_to receive(:send_event).with(event)

      prior_should_capture = Raven.configuration.should_capture
      Raven.configuration.should_capture = Proc.new { false }
      expect(Raven.configuration.should_capture).to receive(:call).with(exception)
      expect(Raven.capture_exception(exception, options)).to be false
      Raven.configuration.should_capture = prior_should_capture
    end
  end

  describe '.capture' do
    context 'given a block' do
      it 'yields to the given block' do
        expect { |b| described_class.capture &b }.to yield_with_no_args
      end

      it 'does not install an exit_hook' do
        expect(described_class).not_to receive(:install_at_exit_hook)
        described_class.capture() {}
      end
    end

    context 'not given a block' do
      let(:options) { { :key => 'value' } }

      it 'does not yield' do
        # As there is no yield matcher that does not require a probe (e.g. this
        # is not valid: expect { |b| described_class.capture }.to_not yield_control),
        # expect that a LocalJumpError, which is raised when yielding when no
        # block is defined, is not raised.
        expect { described_class.capture }.not_to raise_error
      end

      it 'installs an at exit hook' do
        expect(described_class).to receive(:install_at_exit_hook).with(options)
        described_class.capture(options)
      end
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

  describe '.report_status' do
    let(:ready_message) do
      "Raven #{Raven::VERSION} ready to catch errors"
    end

    let(:not_ready_message) do
      "Raven #{Raven::VERSION} configured not to send errors."
    end

    it 'logs a ready message when configured' do
      Raven.configuration.silence_ready = false
      expect(Raven.configuration).to(
        receive(:send_in_current_environment?).and_return(true))
      expect(Raven.logger).to receive(:info).with(ready_message)
      Raven.report_status
    end

    it 'logs not ready message if the config does not send in current environment' do
      Raven.configuration.silence_ready = false
      expect(Raven.configuration).to(
        receive(:send_in_current_environment?).and_return(false))
      expect(Raven.logger).to receive(:info).with(not_ready_message)
      Raven.report_status
    end

    it 'logs nothing if "silence_ready" configuration is true' do
      Raven.configuration.silence_ready = true
      expect(Raven.logger).not_to receive(:info)
      Raven.report_status
    end
  end
end
