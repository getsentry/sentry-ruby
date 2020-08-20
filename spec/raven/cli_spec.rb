require 'spec_helper'
require 'raven/cli'

RSpec.describe Raven::CLI do
  # avoid unexpectedly mutating the shared configuration object
  let(:config) { Raven.configuration.dup }

  context "when there's no error" do
    it "sends an event" do
      event = described_class.test(config.server, true, config)

      expect(event).to be_a(Raven::Event)
      hash = event.to_hash
      expect(hash[:exception][:values][0][:type]).to eq("ZeroDivisionError")
      expect(hash[:exception][:values][0][:value]).to eq("divided by 0")
    end

    it "logs correct values" do
      logger = spy
      allow_any_instance_of(Raven::Instance).to receive(:logger).and_return(logger)

      event = described_class.test(config.server, true, config)

      expect(logger).to have_received(:debug).with("Sending a test event:")
      expect(logger).to have_received(:debug).with("-> event ID: #{event.id}")
      expect(logger).to have_received(:debug).with("Done!")
    end
  end

  context "when there's an error" do
    before do
      # make Configuration#sample_allowed? fail
      config.sample_rate = 2.0
      allow(Random::DEFAULT).to receive(:rand).and_return(3.0)
    end

    it "returns false" do
      event = described_class.test(config.server, true, config)

      expect(event).to eq(false)
    end

    it "logs correct values" do
      logger = spy
      allow_any_instance_of(Raven::Instance).to receive(:logger).and_return(logger)

      described_class.test(config.server, true, config)

      expect(logger).to have_received(:debug).with("Sending a test event:")
      expect(logger).to have_received(:debug).with("An error occurred while attempting to send the event.")
      expect(logger).not_to have_received(:debug).with("Done!")
    end
  end

  context "when with custom environments config" do
    let(:config) { Raven.configuration.dup }

    before do
      config.environments = %w(production test)
    end

    it "still sends the test event" do
      event = Raven::CLI.test(config.server, true, config)

      expect(event).to be_a(Raven::Event)
      expect(config.errors).to be_empty
    end
  end
end
