require "spec_helper"

RSpec.describe Sentry::Resque do
  before do
    perform_basic_setup
  end

  class FailedJob
    def self.perform
      1/0
    end
  end

  class TaggedFailedJob
    def self.perform
      Sentry.set_tags(number: 1)
      1/0
    end
  end

  class MessageJob
    def self.perform(msg)
      Sentry.capture_message(msg)
    end
  end

  class TaggedMessageJob
    def self.perform(msg)
      Sentry.set_tags(number: 1)
      Sentry.capture_message(msg)
    end
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:worker) do
    Resque::Worker.new(:default)
  end

  it "sets correct extra/tags context for each job" do
    Resque::Job.create(:default, MessageJob, "report")

    worker.work(0)

    expect(transport.events.count).to eq(1)
    event = transport.events.last.to_hash
    expect(event[:message]).to eq("report")
    expect(event[:tags]).to eq({ "resque.queue" => "default" })
    expect(event[:contexts][:"Resque"]).to include({ job_class: "MessageJob", arguments: ["report"], queue: "default" })
  end

  it "doesn't leak scope data outside of the job" do
    Resque::Job.create(:default, MessageJob, "report")

    worker.work(0)

    expect(transport.events.count).to eq(1)
    expect(Sentry.get_current_scope.extra).to eq({})
    expect(Sentry.get_current_scope.tags).to eq({})
  end

  it "doesn't share scope data between jobs" do
    Resque::Job.create(:default, TaggedMessageJob, "tagged report")

    worker.work(0)

    expect(transport.events.count).to eq(1)
    event = transport.events.last.to_hash
    expect(event[:message]).to eq("tagged report")
    expect(event[:tags]).to include({ number: 1 })

    Resque::Job.create(:default, MessageJob, "report")

    worker.work(0)

    expect(transport.events.count).to eq(2)
    event = transport.events.last.to_hash
    expect(event[:tags]).to eq({ "resque.queue" => "default" })
  end

  context "when a job failed" do
    it "reports exception" do
      expect do
        Resque::Job.create(:default, FailedJob)
        worker.work(0)
      end.to change { Resque::Stat.get("failed") }.by(1)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_hash

      expect(event[:sdk]).to eq({ name: "sentry.ruby.resque", version: described_class::VERSION })
      expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
      expect(event[:tags]).to eq({ "resque.queue" => "default" })
    end

    it "doesn't leak scope data" do
      expect do
        Resque::Job.create(:default, TaggedFailedJob)
        worker.work(0)
      end.to change { Resque::Stat.get("failed") }.by(1)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_hash

      expect(event[:tags]).to eq({ "resque.queue" => "default", number: 1})
      expect(Sentry.get_current_scope.extra).to eq({})
      expect(Sentry.get_current_scope.tags).to eq({})

      expect do
        Resque::Job.create(:default, FailedJob)
        worker.work(0)
      end.to change { Resque::Stat.get("failed") }.by(1)

      expect(transport.events.count).to eq(2)
      event = transport.events.last.to_hash
      expect(event[:tags]).to eq({ "resque.queue" => "default" })
      expect(Sentry.get_current_scope.extra).to eq({})
      expect(Sentry.get_current_scope.tags).to eq({})
    end
  end

  context "with ActiveJob" do
    require "rails"
    require "active_job"
    require "sentry-rails"

    class AJMessageJob < ActiveJob::Base
      self.queue_adapter = :resque

      def perform(msg)
        Sentry.set_tags(number: 1)
        Sentry.capture_message(msg)
      end
    end

    class AJFailedJob < ActiveJob::Base
      self.queue_adapter = :resque

      def perform
        Sentry.set_tags(number: 2)
        1 / 0
      end
    end

    before do
      ActiveJob::Base.logger = nil

      # because we don't create a full Rails app here, we need to apply sentry-rails' ActiveJob extension manually
      require "sentry/rails/active_job"
      ActiveJob::Base.send(:prepend, Sentry::Rails::ActiveJobExtensions)

      if Sentry.configuration.rails.skippable_job_adapters.empty?
        Sentry.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::ResqueAdapter"
      end
    end

    context "when the job succeeded" do
      before do
        AJMessageJob.perform_later("report from ActiveJob")

        worker.work(0)
      end

      it "doesn't leak scope data" do
        expect(transport.events.count).to eq(1)

        expect(Sentry.get_current_scope.tags).to eq({})
      end

      it "injects ActiveJob information to the event" do
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_hash
        expect(event[:message]).to eq("report from ActiveJob")
        expect(event[:tags]).to match({ "resque.queue" => "default", number: 1 })
        expect(event[:contexts][:"Active-Job"][:job_class]).to eq("AJMessageJob")
      end
    end

    context "when the job failed" do
      before do
        AJFailedJob.perform_later

        expect do
          worker.work(0)
        end.to change { Resque::Stat.get("failed") }.by(1)
      end

      it "doesn't duplicate error reporting" do
        expect(transport.events.count).to eq(1)

        expect(Sentry.get_current_scope.tags).to eq({})
      end

      it "injects ActiveJob information to the event" do
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_hash
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
        expect(event[:tags]).to match({ "resque.queue" => "default", number: 2 })
        expect(event[:contexts][:"Active-Job"][:job_class]).to eq("AJFailedJob")
      end
    end
  end
end


RSpec.describe Sentry::Resque, "not initialized" do
  class FailedJob
    def self.perform
      1/0
    end
  end

  let(:worker) do
    Resque::Worker.new(:default)
  end

  it "doesn't swallow jobs" do
    expect do
      Resque::Job.create(:default, FailedJob)
      worker.work(0)
    end.to change { Resque::Stat.get("failed") }.by(1)
  end
end
