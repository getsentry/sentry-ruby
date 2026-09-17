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
  let(:logger_output) { StringIO.new }
  let(:worker) { worker_class.new(Logger.new(logger_output), interval) }

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

    it "logs run errors and continues running" do
      started = Queue.new
      run_count = 0
      worker.run_block = -> {
        run_count += 1
        started << run_count
        raise Exception, "boom" if run_count == 1
      }

      worker.ensure_thread
      worker.wake
      expect(started.pop).to eq(1)

      worker.wake
      expect(started.pop).to eq(2)
      expect(logger_output.string).to include("run failed: boom")
    end
  end

  describe "#wake" do
    it "runs before the interval expires" do
      worker.ensure_thread
      thread = worker.thread

      worker.wake

      expect(worker.runs.pop).to eq(thread)
    end

    it "does nothing after the worker exits" do
      worker.kill

      expect(worker.wake).to be(false)
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

    it "does nothing after the worker exits" do
      started = Queue.new
      continue = Queue.new
      worker.run_block = -> {
        started << true
        continue.pop
      }

      worker.ensure_thread
      worker.wake
      started.pop

      waiter = Thread.new { worker.wait_until_idle }
      worker.kill

      expect(waiter.join(1)).to eq(waiter)

      continue << true
      expect(worker.thread.join(1)).to eq(worker.thread)
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
