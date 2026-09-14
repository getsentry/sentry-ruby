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
    worker.thread&.join
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
    it "returns true when already idle, even with a zero timeout" do
      expect(worker.wait_until_idle).to be(true)
      expect(worker.wait_until_idle(0)).to be(true)
    end

    it "returns true after a running task finishes" do
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
      started.pop # worker waiting on continue

      waiter_started = Queue.new
      waiter = Thread.new do
        waiter_started << true
        result = worker.wait_until_idle
        completed << :wait
        result
      end
      waiter_started.pop # waiter waiting on idle

      continue << true # resume worker

      expect(completed.pop).to eq(:run)
      expect(completed.pop).to eq(:wait)
      expect(waiter.value).to be(true)
    end

    it "returns false after the timeout if the task is still running" do
      started = Queue.new
      continue = Queue.new
      worker.run_block = -> {
        started << true
        continue.pop
      }

      worker.ensure_thread
      worker.wake
      started.pop # worker will be stuck on continue.pop

      waiter = Thread.new { worker.wait_until_idle(0.01) }

      expect(waiter.join(1)).to eq(waiter)
      expect(waiter.value).to be(false)
      expect(worker.thread).to be_alive
    ensure
      waiter&.kill
      waiter&.join
    end

    it "uses a single deadline across wakeups" do
      worker.wake

      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10, 10, 11, 12)
      expect(worker.idle_condition).to receive(:wait).with(worker.thread_mutex, 2).ordered
      expect(worker.idle_condition).to receive(:wait).with(worker.thread_mutex, 1).ordered

      expect(worker.wait_until_idle(2)).to be(false)
    end

    it "returns false without waiting when work is pending and the timeout is zero" do
      worker.wake
      expect(worker.idle_condition).not_to receive(:wait)

      expect(worker.wait_until_idle(0)).to be(false)
    end

    it "returns true when the worker exits without timing out" do
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
      expect(waiter.value).to be(true)

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
