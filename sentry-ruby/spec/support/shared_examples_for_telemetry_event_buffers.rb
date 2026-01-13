# frozen_string_literal: true

RSpec.shared_examples "telemetry event buffer" do |event_factory:, max_items_config:, enable_config:|
  let(:string_io) { StringIO.new }
  let(:sdk_logger) { ::Logger.new(string_io) }
  let(:client) { Sentry.get_current_client }
  let(:event) { event_factory.call }

  before do
    perform_basic_setup do |config|
      config.sdk_logger = sdk_logger
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

    it "spawns only one thread" do
      expect do
        subject.add_item(event)
      end.to change { Thread.list.count }.by(1)

      expect(subject.thread).to receive(:alive?).and_return(true)

      expect do
        subject.add_item(event)
      end.to change { Thread.list.count }.by(0)
    end

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

  describe "max capacity and dropping events" do
    let(:max_items) { 3 }
    let(:max_items_before_drop) { 10 }

    before do
      subject.instance_variable_set(:@max_items_before_drop, max_items_before_drop)

      # don't clear pending items to allow buffer to grow
      allow(subject).to receive(:clear!)
    end

    it "adds items up to max_items_before_drop capacity" do
      expect {
        max_items_before_drop.times { subject.add_item(event) }
      }.to change { subject.size }.from(0).to(max_items_before_drop)
    end

    it "drops events when buffer reaches max_items_before_drop" do
      max_items_before_drop.times { subject.add_item(event) }

      expect {
        subject.add_item(event)
      }.not_to change { subject.size }

      expect(subject.size).to eq(max_items_before_drop)
    end

    it "records lost event when dropping due to queue overflow" do
      max_items_before_drop.times { subject.add_item(event) }

      expect(client.transport).to receive(:record_lost_event).with(:queue_overflow, subject.data_category)

      subject.add_item(event)
    end

    it "logs debug message when dropping events" do
      max_items_before_drop.times { subject.add_item(event) }
      subject.add_item(event)

      expect(string_io.string).to include("exceeded max capacity, dropping event")
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

        thread = subject.thread

        expect(thread).to be_alive
        expect { subject.flush }.not_to raise_error
        expect(thread).to be_alive
      end
    end
  end
end
