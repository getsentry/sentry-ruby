# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::BackgroundWorker do
  let(:string_io) { StringIO.new }

  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.logger = Logger.new(string_io)
    end
  end

  describe "#initialize" do
    context "when config.async is set" do
      before do
        configuration.async = proc { }
      end

      it "initializes a background_worker with ImmediateExecutor" do
        worker = described_class.new(configuration)

        expect(string_io.string).to match(
          /config.async is set, BackgroundWorker is disabled/
        )

        expect(worker.instance_variable_get(:@executor)).to be_a(Concurrent::ImmediateExecutor)
      end
    end

    context "when config.background_worker_threads is set" do
      it "initializes a background worker with correct number of threads and queue size" do
        configuration.background_worker_threads = 4
        worker = described_class.new(configuration)

        expect(worker.max_queue).to eq(30)
        expect(worker.number_of_threads).to eq(4)
      end
    end

    context "when config.background_worker_threads is 0" do
      before do
        configuration.background_worker_threads = 0
      end

      it "initializes a background_worker with ImmediateExecutor" do
        worker = described_class.new(configuration)

        expect(string_io.string).to match(
          /config.background_worker_threads is set to 0, all events will be sent synchronously/
        )

        expect(worker.instance_variable_get(:@executor)).to be_a(Concurrent::ImmediateExecutor)
      end
    end

    context "when config.background_worker_threads is set" do
      before do
        configuration.background_worker_threads = 5
      end

      it "sets the worker's number_of_threads accordingly" do
        worker = described_class.new(configuration)

        expect(worker.number_of_threads).to eq(5)

        expect(string_io.string).to match(
          /Initializing the Sentry background worker with 5 threads/
        )
      end
    end
  end

  describe "#perform" do
    before { configuration.background_worker_threads = 1 }

    it "logs error message when failed" do
      worker = described_class.new(configuration)

      worker.perform do
        1/0
      end

      sleep(0.1)
      expect(string_io.string).to match(/exception happened in background worker: divided by 0/)
    end
  end

  describe "#shutdown" do
    before { configuration.background_worker_threads = 1 }

    it "logs message about the shutdown" do
      worker = described_class.new(configuration)
      worker.shutdown

      expect(string_io.string).to match(/Shutting down background worker/)
    end
  end

  describe "#full?" do
    it "returns false if not a thread pool" do
      configuration.background_worker_threads = 0
      worker = described_class.new(configuration)
      expect(worker.full?).to eq(false)
    end

    # skipping this on jruby because the capacity check is flaky
    unless RUBY_PLATFORM == "java"
      it "returns true if thread pool and full" do
        configuration.background_worker_threads = 1
        configuration.background_worker_max_queue = 1
        worker = described_class.new(configuration)
        expect(worker.full?).to eq(false)

        2.times { worker.perform { sleep 0.1 } }
        expect(worker.full?).to eq(true)
        sleep 0.2
        expect(worker.full?).to eq(false)
      end
    end
  end
end
