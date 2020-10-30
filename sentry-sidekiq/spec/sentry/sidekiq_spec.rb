require "spec_helper"
require "sentry/sidekiq"
require 'sidekiq/manager'

class HappyWorker
  include Sidekiq::Worker

  def perform
    Sentry.breadcrumbs.record do |crumb|
      crumb.message = "I'm happy!"
    end
    Sentry.get_current_scope.set_tags mood: 'happy'
  end
end

class SadWorker
  include Sidekiq::Worker

  def perform
    Sentry.breadcrumbs.record do |crumb|
      crumb.message = "I'm sad!"
    end
    Sentry.get_current_scope.set_tags :mood => 'sad'

    raise "I'm sad!"
  end
end

class VerySadWorker
  include Sidekiq::Worker

  def perform
    Sentry.breadcrumbs.record do |crumb|
      crumb.message = "I'm very sad!"
    end
    Sentry.get_current_scope.set_tags :mood => 'very sad'

    raise "I'm very sad!"
  end
end

class ReportingWorker
  include Sidekiq::Worker

  def perform
    Sentry.capture_message("I have something to say!")
  end
end

def process_job(processor, klass)
  msg = Sidekiq.dump_json("class" => klass)
  job = Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg)
  processor.instance_variable_set(:'@job', job)

  processor.send(:process, job)
rescue StandardError
  # do nothing
end

RSpec.describe Sentry::Sidekiq do
  before :all do
    Sidekiq.logger = Logger.new(nil)
    perform_basic_setup
  end

  after(:all) do
    # those test jobs will go into the real Redis and be visiable to other sidekiq processes
    # this can affect local testing and development, so we should clear them after each test
    Sidekiq::RetrySet.new.clear
  end

  let(:processor) do
    opts = { :queues => ['default'] }
    manager = Sidekiq::Manager.new(opts)
    manager.workers.first
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  before do
    transport.events = []
  end

  it "has correct meta" do
    expect(Sentry.sdk_meta).to eq(
      { "name" => "sentry.ruby.sidekiq", "version" => Sentry::Sidekiq::VERSION }
    )
  end

  it "registers error handlers and middlewares" do
    expect(Sidekiq.error_handlers).to include(described_class::ErrorHandler)
    expect(Sidekiq.server_middleware.entries.first.klass).to eq(described_class::CleanupMiddleware)
  end

  it "captures the exception" do
    expect { process_job(processor, "SadWorker") }.to change { transport.events.size }.by(1)

    event = transport.events.last.to_json_compatible
    expect(event["message"]).to eq("I'm sad!")
  end

  it "clears context from other workers and captures its own" do
    process_job(processor, "HappyWorker")
    process_job(processor, "SadWorker")

    event = transport.events.last.to_json_compatible

    expect(event["tags"]).to eq("mood" => "sad")
    expect(event["transaction"]).to eq("Sidekiq/SadWorker")
    expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm sad!")
  end

  it "clears context after raising" do
    process_job(processor, "SadWorker")
    process_job(processor, "VerySadWorker")

    event = transport.events.last.to_json_compatible

    expect(event["tags"]).to eq("mood" => "very sad")
    expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm very sad!")
  end

  it "captures exceptions raised during events" do
    Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "Uhoh!" }]
    processor.fire_event(:startup)

    event = transport.events.last.to_json_compatible

    expect(event["message"]).to eq "Uhoh!"
    expect(event["transaction"]).to eq "Sidekiq/startup"
  end

  it "has some context when capturing, even if no exception raised" do
    process_job(processor, "ReportingWorker")

    event = transport.events.last.to_json_compatible

    expect(event["message"]).to eq "I have something to say!"
    expect(event["extra"]["sidekiq"]).to eq("class" => "ReportingWorker", "queue" => "default")
  end
end

