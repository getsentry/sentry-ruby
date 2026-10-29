# frozen_string_literal: true

require "spec_helper"
require "rails"
require "active_job"
require "sentry-rails"
require "sentry/rails/active_job"
require "sentry/resque/active_job_extension"

RSpec.describe Sentry::Resque::ActiveJobExtension do
  class ResqueExtensionJob < ActiveJob::Base
    self.queue_adapter = :resque

    def perform(message); end
  end

  class InlineExtensionJob < ActiveJob::Base
    self.queue_adapter = :inline

    def perform; end
  end

  subject(:extension) { described_class.new }

  let(:enqueued_at) { (Time.now - 2).utc.iso8601(9) }

  let(:raw_resque_message) do
    ResqueExtensionJob.set(queue: :default).perform_later("hello")
    message = Resque.decode(Resque.redis.lpop("queue:default"))
    message["args"][0]["enqueued_at"] = enqueued_at
    Resque.encode(message)
  end

  let(:resque_payload) { Resque.decode(raw_resque_message) }

  let(:job) { ActiveJob::Base.deserialize(resque_payload["args"].first) }

  before do
    ActiveJob::Base.logger = nil
    ActiveJob::Base.send(:prepend, Sentry::Rails::ActiveJobExtensions)
    perform_basic_setup do |config|
      config.resque.active_job_integration = :rails
    end
  end

  it "should be the registered extension for ActiveJob jobs on Resque" do
    expect(Sentry.job_extensions.for(job)).to be_a(described_class)
  end

  describe "#handles?" do
    it "should claim ActiveJob jobs when they run on the Resque adapter" do
      expect(extension.handles?(job)).to be(true)
    end

    it "should not claim ActiveJob jobs when they run on another adapter" do
      expect(extension.handles?(InlineExtensionJob.new)).to be(false)
    end

    it "should not claim raw Resque payloads" do
      expect(extension.handles?(resque_payload)).to be(false)
    end
  end

  it "should give the consumer the Resque origin" do
    expect(extension.span_origin(job: job)).to eq("auto.queue.resque")
  end

  it "should name the transaction after the ActiveJob class" do
    expect(extension.transaction_name(job: job)).to eq("ResqueExtensionJob")
  end

  it "should capture exceptions under the Resque integration" do
    expect(extension.integration(job: job)).to eq(Sentry::Resque)
  end

  describe "#scope_data" do
    it "should tag the Resque queue and add the Active-Job context" do
      Sentry.configuration.data_collection.queues = true

      data = extension.scope_data(job: job)

      expect(data[:tags]).to eq("resque.queue" => "default")
      expect(data[:contexts][:"Active-Job"]).to include(
        job_class: "ResqueExtensionJob",
        job_id: job.job_id,
        arguments: ["hello"],
        executions: 0,
        exception_executions: {},
        locale: "en",
        enqueued_at: enqueued_at,
        queue: "default"
      )
    end

    it "should leave the job arguments out of the Active-Job context when queue data collection is off" do
      Sentry.configuration.data_collection.queues = false

      context = extension.scope_data(job: job)[:contexts][:"Active-Job"]

      expect(context).not_to have_key(:arguments)
      expect(context).to include(job_id: job.job_id, queue: "default")
    end
  end

  describe "#messaging_data" do
    it "should describe the Resque message" do
      data = extension.messaging_data(job: job)

      expect(data).to include(
        system: "resque",
        message_id: job.job_id,
        destination: "default",
        body_size: raw_resque_message.bytesize
      )
      expect(data[:receive_latency]).to be >= 2000
    end
  end
end
