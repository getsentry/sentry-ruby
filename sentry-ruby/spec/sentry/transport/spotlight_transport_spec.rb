# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::SpotlightTransport do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.spotlight = true
      config.logger = Logger.new(nil)
    end
  end

  let(:custom_configuration) do
    Sentry::Configuration.new.tap do |config|
      config.spotlight = 'http://foobar@test.com'
      config.logger = Logger.new(nil)
    end
  end

  let(:client) { Sentry::Client.new(configuration) }
  let(:event) { client.event_from_message("foobarbaz") }
  let(:data) do
    subject.serialize_envelope(subject.envelope_from_event(event.to_hash)).first
  end

  subject { described_class.new(configuration) }

  it 'logs a debug message during initialization' do
    string_io = StringIO.new
    configuration.logger = Logger.new(string_io)

    subject

    expect(string_io.string).to include('sentry: [Spotlight] initialized for url http://localhost:8969/stream')
  end

  describe '#endpoint' do
    it 'returs correct endpoint' do
      expect(subject.endpoint).to eq('/stream')
    end
  end

  describe '#conn' do
    it 'returns connection with default host' do
      expect(subject.conn).to be_a(Net::HTTP)
      expect(subject.conn.address).to eq('localhost')
      expect(subject.conn.port).to eq(8969)
      expect(subject.conn.use_ssl?).to eq(false)
    end

    it 'returns connection with overriden host' do
      subject = described_class.new(custom_configuration)
      expect(subject.conn).to be_a(Net::HTTP)
      expect(subject.conn.address).to eq('test.com')
      expect(subject.conn.port).to eq(80)
      expect(subject.conn.use_ssl?).to eq(false)
    end
  end

  describe '#send_data' do
    it 'fails a maximum of three times and logs disable once' do
      string_io = StringIO.new
      configuration.logger = Logger.new(string_io)
      configuration.logger.level = :debug

      allow(::Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

      3.times do
        expect do
          subject.send_data(data)
        end.to raise_error(Sentry::ExternalError)
      end

      3.times do
        expect do
          subject.send_data(data)
        end.not_to raise_error
      end

      expect(string_io.string.scan('sentry: [Spotlight] disabling because of too many request failures').size).to eq(1)
    end
  end
end
