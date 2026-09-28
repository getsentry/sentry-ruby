# frozen_string_literal: true

RSpec.shared_examples "telemetry event buffer" do |event_factory:, max_items_config:|
  let(:string_io) { StringIO.new }
  let(:sdk_logger) { ::Logger.new(string_io) }
  let(:client) { Sentry.get_current_client }
  let(:event) { event_factory.call }

  before do
    perform_basic_setup do |config|
      config.sdk_logger = sdk_logger
      config.background_worker_threads = 0
      config.public_send(:"#{max_items_config}=", max_items)
    end

    Sentry.background_worker = Sentry::BackgroundWorker.new(Sentry.configuration)
  end

  after do
    subject.kill
    subject.thread&.join
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

    it "auto-flushes pending items to the client using the buffer thread when the number of items reaches max_items" do
      thread = nil
      expect(client).to receive(:send_envelope) do
        thread = Thread.current
      end

      3.times { subject.add_item(event) }

      subject.flush
      expect(thread).to eq(subject.thread)
      expect(subject).to be_empty
    end
  end

  describe "#flush" do
    let(:max_items) { 3 }

    it "does not start a thread for an unused buffer" do
      expect(subject).not_to receive(:ensure_thread)
      expect(subject).not_to receive(:wake)
      expect(subject).not_to receive(:wait_until_idle)

      subject.flush

      expect(subject.thread).to be_nil
    end

    it "flushes remaining items on the buffer thread with a two-second timeout" do
      sending_thread = nil
      expect(client).to receive(:send_envelope) do
        sending_thread = Thread.current
      end
      expect(subject).to receive(:wait_until_idle).with(2).and_call_original

      subject.add_item(event)
      expect(subject.flush).to be(true)

      expect(sending_thread).to eq(subject.thread)
      expect(subject).to be_empty
    end

    it "does nothing when the buffer thread is dead" do
      subject.add_item(event)
      subject.thread.kill.join

      expect(subject).not_to receive(:ensure_thread)
      expect(subject).not_to receive(:wake)
      expect(subject).not_to receive(:wait_until_idle)
      expect(client).not_to receive(:send_envelope)

      subject.flush

      expect(subject.size).to eq(1)
      expect(subject.thread).not_to be_alive
    end

    it "waits for an in-flight send and then flushes remaining items" do
      send_started = Queue.new
      continue_send = Queue.new
      allow(client).to receive(:send_envelope) do |envelope|
        send_started << envelope
        continue_send.pop
      end

      max_items.times { subject.add_item(event) }
      expect(send_started.pop.items.first.headers[:item_count]).to eq(max_items)
      subject.add_item(event)

      flusher = Thread.new { subject.flush }
      continue_send << true

      expect(send_started.pop.items.first.headers[:item_count]).to eq(1)
      expect(flusher.join(0.01)).to be_nil
      continue_send << true

      expect(flusher.join(1)).to eq(flusher)
      expect(flusher.value).to be(true)
      expect(subject).to be_empty
    ensure
      flusher&.kill
      flusher&.join
    end

    context "when sending stalls" do
      let(:send_started) { Queue.new }
      let(:continue_send) { Queue.new }

      before do
        stub_const("Sentry::TelemetryEventBuffer::FLUSH_TIMEOUT", 0.01)
        allow(client).to receive(:send_envelope) do
          send_started << true
          continue_send.pop
        end
      end

      it "returns after the timeout when flushing remaining items" do
        subject.add_item(event)

        flusher = Thread.new { subject.flush }
        send_started.pop

        expect(flusher.join(1)).to eq(flusher)
        expect(flusher.value).to be(false)
        expect(subject.thread).to be_alive
      ensure
        flusher&.kill
        flusher&.join
      end

      it "returns after the timeout when a send is already in flight" do
        max_items.times { subject.add_item(event) }
        send_started.pop
        subject.add_item(event)

        flusher = Thread.new { subject.flush }

        expect(flusher.join(1)).to eq(flusher)
        expect(flusher.value).to be(false)
        expect(subject.size).to eq(1)
        expect(subject.thread).to be_alive
      ensure
        flusher&.kill
        flusher&.join
      end
    end
  end

  describe "sending" do
    let(:max_items) { 3 }

    it "does not hold the mutex while sending" do
      send_started = Queue.new
      continue_send = Queue.new
      add_finished = Queue.new

      allow(client).to receive(:send_envelope) do
        send_started << true
        continue_send.pop
      end

      # trigger a flush
      sender = Thread.new do
        max_items.times { subject.add_item(event) }
      end

      # start sending, will block till continue_send
      send_started.pop

      Thread.new do
        subject.add_item(event)
        add_finished << true
      end

      # sending shouldn't block the add
      expect(add_finished.pop).to be(true)
      continue_send << true
      sender.join
    end
  end

  describe "multi-threaded access" do
    let(:max_items) { 30 }

    it "thread-safely handles concurrent access" do
      expect(client).to receive(:send_envelope).at_least(:once)

      threads = 3.times.map do
        Thread.new do
          (21..30).to_a.sample.times { subject.add_item(event) }
        end
      end

      threads.each(&:join)

      subject.flush

      expect(subject).to be_empty
    end
  end

  describe "max capacity and dropping events" do
    let(:max_items) { max_items_before_drop + 1 }
    let(:max_items_before_drop) { 10 }

    before do
      subject.instance_variable_set(:@max_items_before_drop, max_items_before_drop)
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

      expect(client.transport).to receive(:record_lost_event).with(:queue_overflow, subject.data_category, num_bytes: a_value > 0)

      subject.add_item(event)
    end

    it "logs debug message when dropping events" do
      max_items_before_drop.times { subject.add_item(event) }
      subject.add_item(event)

      expect(string_io.string).to include("exceeded max capacity, dropping event")
    end
  end

  describe "re-entrancy protection" do
    let(:max_items) { 3 }

    it "does not deadlock when add_item is called re-entrantly from send_items" do
      reentrant_calls = 0

      allow(client).to receive(:send_envelope) do
        reentrant_calls += 1
        # Simulate instrumentation calling back into the buffer mid-send
        subject.add_item(event)
        # also simulate a second re-entrant call to be sure
        subject.add_item(event)
      end

      expect {
        3.times { subject.add_item(event) }
      }.not_to raise_error

      subject.flush
      expect(reentrant_calls).to be >= 1
    end

    it "silently drops the re-entrant item rather than raising" do
      items_sent = []

      allow(client).to receive(:send_envelope) do |envelope|
        items_sent << :sent
        subject.add_item(event)  # re-entrant; must be dropped, not raise
      end

      3.times { subject.add_item(event) }

      subject.flush
      expect(items_sent).not_to be_empty
      expect(string_io.string).not_to include("deadlock")
    end

    it "does not add items from the buffer thread" do
      worker_thread = Queue.new

      allow(client).to receive(:send_envelope) do
        worker_thread << Thread.current
        subject.add_item(event)
      end

      3.times { subject.add_item(event) }

      expect(worker_thread.pop).to eq(subject.thread)
      subject.wait_until_idle
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

        subject.flush
        expect(string_io.string).to include("Failed to send #{event.class}")
      end

      it "clears the buffer after a failed send to avoid memory buildup" do
        3.times { subject.add_item(event) }

        subject.flush
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
