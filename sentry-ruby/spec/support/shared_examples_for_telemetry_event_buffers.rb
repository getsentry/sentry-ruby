# frozen_string_literal: true

RSpec.shared_examples "telemetry event buffer" do |event_factory:, max_items_config:, enable_config:|
  let(:string_io) { StringIO.new }
  let(:logger) { ::Logger.new(string_io) }
  let(:client) { double(Sentry::Client) }
  let(:event) { event_factory.call }

  before do
    perform_basic_setup do |config|
      config.sdk_logger = logger
      config.background_worker_threads = 0
      config.public_send(:"#{max_items_config}=", max_items)
      config.public_send(:"#{enable_config}=", true)
    end

    Sentry.background_worker = Sentry::BackgroundWorker.new(Sentry.configuration)
  end

  after do
    Sentry.background_worker = Class.new { def shutdown; end; }.new
  end

  describe "#add_item" do
    let(:max_items) { 3 }

    it "does nothing when there are no pending items" do
      expect(client).not_to receive(:capture_envelope)

      subject.flush

      expect(sentry_envelopes.size).to be(0)
    end

    it "does nothing when the number of items is less than max_items" do
      expect(client).to_not receive(:send_envelope)

      2.times { subject.add_item(event) }
    end

    it "auto-flushes pending items to the client when the number of items reaches max_items" do
      expect(client).to receive(:send_envelope)

      3.times { subject.add_item(event) }

      expect(subject).to be_empty
    end
  end

  describe "multi-threaded access" do
    let(:max_items) { 30 }

    it "thread-safely handles concurrent access" do
      expect(client).to receive(:send_envelope).exactly(3).times

      threads = 3.times.map do
        Thread.new do
          (20..30).to_a.sample.times { subject.add_item(event) }
        end
      end

      threads.each(&:join)

      subject.flush

      expect(subject).to be_empty
    end
  end

  describe "error handling" do
    let(:max_items) { 3 }

    let(:error) { Errno::ECONNREFUSED.new("Connection refused") }

    context "when send_envelope raises an exception" do
      before do
        allow(client).to receive(:send_envelope).and_raise(error)
      end

      it "does not propagate exception from add_item when buffer is full" do
        expect {
          3.times { subject.add_item(event) }
        }.not_to raise_error
      end

      it "does not propagate exception from flush" do
        2.times { subject.add_item(event) }

        expect {
          subject.flush
        }.not_to raise_error
      end

      it "logs the error to sdk_logger" do
        3.times { subject.add_item(event) }

        expect(string_io.string).to include("Failed to send #{event.class}")
      end

      it "clears the buffer after a failed send to avoid memory buildup" do
        3.times { subject.add_item(event) }

        expect(subject).to be_empty
      end
    end

    context "when background thread encounters an error" do
      let(:max_items) { 100 }

      before do
        allow(client).to receive(:send_envelope).and_raise(error)
      end

      it "keeps the background thread alive after an error" do
        subject.add_item(event)
        subject.start

        thread = subject.instance_variable_get(:@thread)

        expect(thread).to be_alive
        expect { subject.flush }.not_to raise_error
        expect(thread).to be_alive
      end
    end
  end
end
