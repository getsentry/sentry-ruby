# frozen_string_literal: true

RSpec.describe Sentry::DummyTransport do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.sdk_logger = Logger.new(nil)
    end
  end

  subject(:transport) { described_class.new(configuration) }

  it "keeps every envelope sent from concurrent threads" do
    threads = Array.new(8) do
      Thread.new { 500.times { transport.send_envelope(Sentry::Envelope.new) } }
    end
    threads.each(&:join)

    expect(transport.envelopes.size).to eq(4000)
    expect(transport.envelopes).to all(be_a(Sentry::Envelope))
  end
end
