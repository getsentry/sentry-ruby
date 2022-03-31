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
        configuration.async = proc {}
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
        worker = described_class.new(configuration)

        expect(worker.max_queue).to eq(30)
        expect(worker.number_of_threads).to eq(Concurrent.processor_count)
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
          /Initializing the background worker with 5 threads/
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
end
