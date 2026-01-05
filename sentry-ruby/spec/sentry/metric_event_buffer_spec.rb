# frozen_string_literal: true

RSpec.describe Sentry::MetricEventBuffer do
  subject(:metric_event_buffer) { described_class.new(Sentry.configuration, client) }

  let(:string_io) { StringIO.new }
  let(:logger) { ::Logger.new(string_io) }
  let(:client) { double(Sentry::Client) }
  let(:metric_event) do
    Sentry::MetricEvent.new(
      name: "test.metric",
      type: :counter,
      value: 1
    )
  end

  before do
    perform_basic_setup do |config|
      config.sdk_logger = logger
      config.background_worker_threads = 0
      config.max_metric_events = max_metric_events
      config.enable_metrics = true
    end

    Sentry.background_worker = Sentry::BackgroundWorker.new(Sentry.configuration)
  end

  after do
    Sentry.background_worker = Class.new { def shutdown; end; }.new
  end

  describe "#add_metric" do
    let(:max_metric_events) { 3 }

    it "does nothing when there are no pending metrics" do
      expect(client).not_to receive(:capture_envelope)

      metric_event_buffer.flush

      expect(sentry_envelopes.size).to be(0)
    end

    it "does nothing when the number of metrics is less than max_metrics" do
      expect(client).to_not receive(:send_metrics)

      2.times { metric_event_buffer.add_metric(metric_event) }
    end

    it "auto-flushes pending metrics to the client when the number of metrics reaches max_metrics" do
      expect(client).to receive(:send_metrics)

      3.times { metric_event_buffer.add_metric(metric_event) }

      expect(metric_event_buffer).to be_empty
    end
  end

  describe "multi-threaded access" do
    let(:max_metric_events) { 30 }

    it "thread-safely handles concurrent access" do
      expect(client).to receive(:send_metrics).exactly(3).times

      threads = 3.times.map do
        Thread.new do
          (20..30).to_a.sample.times { metric_event_buffer.add_metric(metric_event) }
        end
      end

      threads.each(&:join)

      metric_event_buffer.flush

      expect(metric_event_buffer).to be_empty
    end
  end

  describe "error handling" do
    let(:max_metric_events) { 3 }

    let(:error) { Errno::ECONNREFUSED.new("Connection refused") }

    context "when send_metrics raises an exception" do
      before do
        allow(client).to receive(:send_metrics).and_raise(error)
      end

      it "does not propagate exception from add_metric when buffer is full" do
        expect {
          3.times { metric_event_buffer.add_metric(metric_event) }
        }.not_to raise_error
      end

      it "does not propagate exception from flush" do
        2.times { metric_event_buffer.add_metric(metric_event) }

        expect {
          metric_event_buffer.flush
        }.not_to raise_error
      end

      it "logs the error to sdk_logger" do
        3.times { metric_event_buffer.add_metric(metric_event) }

        expect(string_io.string).to include("Failed to send metrics")
      end

      it "clears the buffer after a failed send to avoid memory buildup" do
        3.times { metric_event_buffer.add_metric(metric_event) }

        expect(metric_event_buffer).to be_empty
      end
    end

    context "when background thread encounters an error" do
      let(:max_metric_events) { 100 }

      before do
        allow(client).to receive(:send_metrics).and_raise(error)
      end

      it "keeps the background thread alive after an error" do
        metric_event_buffer.add_metric(metric_event)
        metric_event_buffer.start

        thread = metric_event_buffer.instance_variable_get(:@thread)

        expect(thread).to be_alive
        expect { metric_event_buffer.flush }.not_to raise_error
        expect(thread).to be_alive
      end
    end
  end
end
