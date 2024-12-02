# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::BackpressureMonitor do
  let(:string_io) { StringIO.new }

  before do
    perform_basic_setup do |config|
      config.enable_backpressure_handling = true
      config.logger = Logger.new(string_io)
    end
  end

  let(:configuration) { Sentry.configuration }
  let(:client) { Sentry.get_current_client }
  let(:transport) { client.transport }
  let(:background_worker) { Sentry.background_worker }

  subject { described_class.new(configuration, client) }

  describe '#healthy?' do
    it 'returns true by default' do
      expect(subject.healthy?).to eq(true)
    end

    it 'returns false when unhealthy' do
      expect(transport).to receive(:any_rate_limited?).and_return(true)
      subject.run
      expect(subject.healthy?).to eq(false)
    end

    it 'spawns new thread' do
      expect { subject.healthy? }.to change { Thread.list.count }.by(1)
      expect(subject.instance_variable_get(:@thread)).to be_a(Thread)
    end

    it 'spawns only one thread' do
      expect { subject.healthy? }.to change { Thread.list.count }.by(1)
      thread = subject.instance_variable_get(:@thread)
      expect(thread).to receive(:alive?).and_return(true)
      expect { subject.healthy? }.to change { Thread.list.count }.by(0)
    end

    context 'when thread creation fails' do
      before do
        expect(Thread).to receive(:new).and_raise(ThreadError)
      end

      it 'does not create new thread' do
        expect { subject.healthy? }.to change { Thread.list.count }.by(0)
      end

      it 'returns true (the default)' do
        expect(subject.healthy?).to eq(true)
      end

      it 'logs error' do
        subject.healthy?
        expect(string_io.string).to include("[#{described_class.name}] thread creation failed")
      end
    end

    context 'when killed' do
      before { subject.kill }

      it 'returns true (the default)' do
        expect(subject.healthy?).to eq(true)
      end

      it 'does not create new thread' do
        expect(Thread).not_to receive(:new)
        expect { subject.healthy? }.to change { Thread.list.count }.by(0)
      end
    end
  end

  # thread behavior is tested above in healthy?
  describe '#downsample_factor' do
    it 'returns 0 by default' do
      expect(subject.downsample_factor).to eq(0)
    end

    it 'increases when unhealthy upto limit' do
      allow(transport).to receive(:any_rate_limited?).and_return(true)

      10.times do |i|
        subject.run
        expect(subject.downsample_factor).to eq(i + 1)
      end

      2.times do |i|
        subject.run
        expect(subject.downsample_factor).to eq(10)
      end
    end
  end

  describe '#run' do
    it 'logs behavior' do
      allow(background_worker).to receive(:full?).and_return(true)
      subject.run
      expect(string_io.string).to match(/\[BackpressureMonitor\] health check negative, downsampling with a factor of 1/)

      allow(background_worker).to receive(:full?).and_return(false)
      subject.run
      expect(string_io.string).to match(/\[BackpressureMonitor\] health check positive, reverting to normal sampling/)
    end
  end

  describe '#kill' do
    it 'kills the thread and logs a message' do
      subject.healthy?
      expect(subject.instance_variable_get(:@thread)).to receive(:kill)
      subject.kill
      expect(string_io.string).to include("[#{described_class.name}] thread killed")
    end
  end
end
