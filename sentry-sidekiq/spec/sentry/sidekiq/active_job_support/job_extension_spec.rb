# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Sidekiq::ActiveJobSupport::JobExtension do
  subject(:extension) { described_class.new }

  let(:job) do
    {
      "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped" => "HardJob",
      "jid" => "123456",
      "queue" => "default",
      "args" => [{ "job_class" => "HardJob", "arguments" => [{ "_aj_globalid" => "gid://app/User/1" }] }]
    }
  end

  describe "#transaction_name" do
    it "names the job after the ActiveJob class it wraps" do
      expect(extension.transaction_name(job: job)).to eq("Sidekiq/HardJob")
    end
  end

  describe "#error_context" do
    it "strips ActiveJob's reserved key prefixes from the job" do
      context = extension.error_context(context: "Job raised exception", job: job)

      expect(context["args"].first["arguments"]).to eq([{ "globalid" => "gid://app/User/1" }])
      expect(context).to include(context: "Job raised exception", "jid" => "123456", "wrapped" => "HardJob")
    end

    it "strips the prefixes at every level of the context" do
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
