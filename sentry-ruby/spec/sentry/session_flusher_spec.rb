require "spec_helper"

RSpec.describe Sentry::SessionFlusher do
  let(:string_io) { StringIO.new }

  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.release = 'test-release'
      config.environment = 'test'
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
      config.logger = Logger.new(string_io)
    end
  end

  let(:client) { Sentry::Client.new(configuration) }
  let(:transport) { client.transport }
  subject { described_class.new(configuration, client) }

  before do
    Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
  end

  describe "#initialize" do
    context "when config.release is nil" do
      before { configuration.release = nil }

      it "logs debug message" do
        flusher = described_class.new(configuration, client)

        expect(string_io.string).to match(
          /Sessions won't be captured without a valid release/
        )
      end
    end
  end

  describe "#flush" do
    it "early returns with no pending_aggregates" do
      expect(subject.instance_variable_get(:@pending_aggregates)).to eq({})

      expect do
        subject.flush
      end.not_to change { transport.envelopes.count }
    end

    context "with pending aggregates" do
      let(:now) do
        time = Time.now.utc
        Time.utc(time.year, time.month, time.day, time.hour, time.min)
      end

      before do
        Timecop.freeze(now) do
          10.times do
            session = Sentry::Session.new
            session.close
            subject.add_session(session)
          end

          5.times do
            session = Sentry::Session.new
            session.update_from_exception
            session.close
            subject.add_session(session)
          end
        end
      end

      it "captures pending_aggregates in background worker" do
        expect do
          subject.flush
        end.to change { transport.envelopes.count }.by(1)

        envelope = transport.envelopes.first
        expect(envelope.items.length).to eq(1)
        item = envelope.items.first
        expect(item.type).to eq('sessions')
        expect(item.payload[:attrs]).to eq({ release: 'test-release', environment: 'test' })
        expect(item.payload[:aggregates].first).to eq({ exited: 10, errored: 5, started: now.iso8601 })
      end
    end
  end

  describe "#add_session" do
    let(:session) do
      session = Sentry::Session.new
      session.close
      session
    end

    context "when config.release is nil" do
      before { configuration.release = nil }

      it "noops" do
        flusher = described_class.new(configuration, client)
        flusher.add_session(session)
        expect(flusher.instance_variable_get(:@pending_aggregates)).to eq({})
      end
    end

    it "spawns new thread" do
      expect do
        subject.add_session(session)
      end.to change { Thread.list.count }.by(1)

      expect(subject.instance_variable_get(:@thread)).to be_a(Thread)
    end

    it "spawns only one thread" do
      expect do
        subject.add_session(session)
      end.to change { Thread.list.count }.by(1)

      thread = subject.instance_variable_get(:@thread)
      expect(thread).to receive(:alive?).and_return(true)

      expect do
        subject.add_session(session)
      end.to change { Thread.list.count }.by(0)
    end

    it "adds session to pending_aggregates" do
      subject.add_session(session)
      pending_aggregates = subject.instance_variable_get(:@pending_aggregates)
      expect(pending_aggregates.keys.first).to be_a(Time)
      expect(pending_aggregates.values.first).to include({ errored: 0, exited: 1 })
    end

    context "when thread creation fails" do
      before do
        expect(Thread).to receive(:new).and_raise(ThreadError)
      end

      it "doesn't create new thread" do
        expect do
          subject.add_session(session)
        end.to change { Thread.list.count }.by(0)
      end

      it "noops" do
        subject.add_session(session)
        expect(subject.instance_variable_get(:@pending_aggregates)).to eq({})
      end

      it "logs error" do
        subject.add_session(session)
        expect(string_io.string).to match(/Session flusher thread creation failed/)
      end
    end

    context "when killed" do
      before do
        subject.kill
      end

      it "noops" do
        subject.add_session(session)
        expect(subject.instance_variable_get(:@pending_aggregates)).to eq({})
      end

      it "doesn't create new thread" do
        expect(Thread).not_to receive(:new)

        expect do
          subject.add_session(session)
        end.to change { Thread.list.count }.by(0)
      end
    end
  end

  describe "#kill" do
    it "logs message when killing the thread" do
      subject.kill
      expect(string_io.string).to match(/Killing session flusher/)
    end
  end
end
