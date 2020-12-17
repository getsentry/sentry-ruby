require "spec_helper"

RSpec.describe Sentry::BackgroundWorker do
  let(:string_io) { StringIO.new }

  describe "#initialize" do
    let(:configuration) do
      Sentry::Configuration.new.tap do |config|
        config.logger = Logger.new(string_io)
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

      it "initializes a background worker that process jobs synchronously" do
        worker = described_class.new(configuration)

        expect(string_io.string).to match(
          /config.background_worker_threads is set to 0, all events will be sent synchronously/
        )

        # verify the behavior of executor instead of checking its class
        counter = 0

        worker.perform do
          sleep 0.1
          counter += 1
        end

        expect(counter).to eq(1)
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
