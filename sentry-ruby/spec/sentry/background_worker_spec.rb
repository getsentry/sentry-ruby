require "spec_helper"

RSpec.describe Sentry::BackgroundWorker do
  let(:string_io) { StringIO.new }

  describe "#initialize" do
    let(:configuration) do
      Sentry::Configuration.new.tap do |config|
        config.logger = Logger.new(string_io)
      end
    end

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
          /initialized a background worker with 5 threads/
        )
      end
    end
  end
end
