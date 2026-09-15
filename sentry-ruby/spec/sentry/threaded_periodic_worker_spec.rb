# frozen_string_literal: true

RSpec.describe Sentry::ThreadedPeriodicWorker do
  let(:worker_class) do
    Class.new(described_class) do
      attr_reader :runs
      attr_writer :run_block

      def initialize(*args)
        super
        @runs = Queue.new
      end

      def run
        @run_block ? @run_block.call : @runs << Thread.current
      end
    end
  end

  let(:interval) { 60 }
  let(:worker) { worker_class.new(Logger.new(nil), interval) }

  after do
    worker.kill
  end

  describe "#initialize" do
    it "does not start a thread just by initialization" do
      expect(worker.thread).to be_nil
    end
  end

  describe "#ensure_thread" do
    context "when the interval expires" do
      let(:interval) { 0 }

      it "runs on the worker thread" do
        worker.ensure_thread

        expect(worker.runs.pop).to eq(worker.thread)
      end
    end

    it "creates only one thread when ensured concurrently" do
      barrier = Queue.new
      callers = 2.times.map do
        Thread.new do
          barrier.pop
          worker.ensure_thread
        end
      end

      expect(Thread).to receive(:new).once.and_call_original
      callers.each { barrier << true }
      callers.each(&:join)
    end
  end

  describe "#wake" do
    it "runs before the interval expires" do
      worker.ensure_thread
      thread = worker.thread

      worker.wake

      expect(worker.runs.pop).to eq(thread)
    end
  end

  describe "#wait_until_idle" do
    it "waits for a running task to finish" do
      started = Queue.new
      continue = Queue.new
      completed = Queue.new
      worker.run_block = -> {
        started << true
        continue.pop
        completed << :run
      }

      worker.ensure_thread
      worker.wake
      started.pop

      waiter_started = Queue.new
      waiter = Thread.new do
        waiter_started << true
        worker.wait_until_idle
        completed << :wait
      end
      waiter_started.pop

      continue << true

      expect(completed.pop).to eq(:run)
      expect(completed.pop).to eq(:wait)
      waiter.join
    end
  end

  describe "#kill" do
    it "stops the worker thread" do
      worker.ensure_thread
      thread = worker.thread

      worker.kill
      thread.join

      expect(thread).not_to be_alive

      result = nil
      expect { result = worker.ensure_thread }.not_to change { Thread.list.count }
      expect(result).to be(false)
    end
  end
end
