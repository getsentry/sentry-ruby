# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Sidekiq::ActiveJobSupport::JobExtension do
  subject(:extension) { described_class.new }

  before do
    perform_basic_setup
  end

  let(:active_job_metadata) do
    {
      "job_class" => "HardJob",
      "job_id" => "aj-123",
      "executions" => 0,
      "locale" => "en",
      "enqueued_at" => "2026-11-05T09:00:00Z"
    }
  end

  let(:job) do
    {
      "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped" => "HardJob",
      "jid" => "123456",
      "queue" => "default",
      "tags" => ["billing"],
      "args" => [active_job_metadata.merge("arguments" => [{ "_aj_globalid" => "gid://app/User/1" }])]
    }
  end

  let(:job_without_arguments) do
    job.merge("args" => [active_job_metadata])
  end

  describe "#scope_data" do
    it "keeps the ActiveJob metadata but not its arguments when queue data collection is off" do
      Sentry.configuration.data_collection.queues = false

      data = extension.scope_data(job: job)

      expect(data[:contexts]).to eq(sidekiq: job_without_arguments)
      expect(data[:tags]).to eq(queue: "default", jid: "123456", "sidekiq.billing": true)
    end

    it "reports the whole job when queue data collection is on" do
      Sentry.configuration.data_collection.queues = true

      data = extension.scope_data(job: job)

      expect(data[:contexts]).to eq(sidekiq: job)
      expect(data[:tags]).to eq(queue: "default", jid: "123456", "sidekiq.billing": true)
    end
  end

  describe "#transaction_name" do
    it "names the job after the ActiveJob class it wraps" do
      expect(extension.transaction_name(job: job)).to eq("Sidekiq/HardJob")
    end
  end

  describe "#error_context" do
    it "strips ActiveJob's reserved key prefixes from the job" do
      Sentry.configuration.data_collection.queues = true
      context = extension.error_context(context: "Job raised exception", job: job)

      expect(context["args"].first["arguments"]).to eq([{ "globalid" => "gid://app/User/1" }])
      expect(context).to include(context: "Job raised exception", "jid" => "123456", "wrapped" => "HardJob")
    end

    it "keeps the ActiveJob metadata but not its arguments or the raw job when queue data collection is off" do
      Sentry.configuration.data_collection.queues = false

      context = extension.error_context(context: "Internal exception!", job: job, jobstr: Sidekiq.dump_json(job))

      expect(context).to eq(job_without_arguments.merge(context: "Internal exception!"))
    end

    it "strips the prefixes at every level of the context" do
      Sentry.configuration.data_collection.queues = true
      context = extension.error_context(_aj_globalid: "gid://app/model/id", arguments: { key: "value", _aj_symbol_keys: ["key"] })

      expect(context).to eq("globalid" => "gid://app/model/id", :arguments => { :key => "value", "symbol_keys" => ["key"] })
    end
  end

  describe "selection" do
    it "handles ActiveJob jobs, which Sidekiq receives wrapped" do
      expect(Sentry::Sidekiq.job_extension_for(job)).to be_a(described_class)
    end

    it "leaves plain Sidekiq jobs and errors without a job to the Sidekiq extension" do
      expect(Sentry::Sidekiq.job_extension_for(job.reject { |key, _value| key == "wrapped" })).to equal(Sentry::Sidekiq.job_extension)
      expect(Sentry::Sidekiq.job_extension_for(nil)).to equal(Sentry::Sidekiq.job_extension)
    end
  end
end
