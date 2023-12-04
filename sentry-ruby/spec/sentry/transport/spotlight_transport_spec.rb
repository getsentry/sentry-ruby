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

  subject { described_class.new(configuration) }

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
end
