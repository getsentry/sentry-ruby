require 'spec_helper'

# sidekiq only enables server config when the CLI class is loaded
# so we need to load the CLI class to achieve full integration in test environment
require 'sidekiq/cli'
require 'sidekiq/manager'

require 'raven/integrations/sidekiq'

class HappyWorker
  include Sidekiq::Worker

  def perform
    Raven.breadcrumbs.record do |crumb|
      crumb.message = "I'm happy!"
    end
    Raven.tags_context :mood => 'happy'
  end
end

class SadWorker
  include Sidekiq::Worker

  def perform
    Raven.breadcrumbs.record do |crumb|
      crumb.message = "I'm sad!"
    end
    Raven.tags_context :mood => 'sad'

    raise "I'm sad!"
  end
end

class VerySadWorker
  include Sidekiq::Worker

  def perform
    Raven.breadcrumbs.record do |crumb|
      crumb.message = "I'm very sad!"
    end
    Raven.tags_context :mood => 'very sad'

    raise "I'm very sad!"
  end
end

class ReportingWorker
  include Sidekiq::Worker

  def perform
    Raven.capture_message("I have something to say!")
  end
end

RSpec.describe "Sidekiq full-stack integration" do
  before :all do
    Sidekiq.logger = Logger.new(nil)
  end

  after(:all) do
    # those test jobs will go into the real Redis and be visiable to other sidekiq processes
    # this can affect local testing and development, so we should clear them after each test
    Sidekiq::RetrySet.new.clear
  end

  def process_job(klass)
    msg = Sidekiq.dump_json("class" => klass)
    job = Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg)
    @processor.instance_variable_set(:'@job', job)

    @processor.send(:process, job)
  rescue StandardError
    # do nothing
  end

  before do
    opts = { :queues => ['default'] }
    manager = Sidekiq::Manager.new(opts)
    @processor = manager.workers.first
  end

  it "actually captures an exception" do
    expect { process_job("SadWorker") }.to change { Raven.client.transport.events.size }.by(1)

    event = JSON.parse(Raven.client.transport.events.last[1])
    expect(event["logentry"]["message"]).to eq("I'm sad!")
  end

  it "clears context from other workers and captures its own" do
    process_job("HappyWorker")
    process_job("SadWorker")

    event = JSON.parse(Raven.client.transport.events.last[1])

    expect(event["tags"]).to eq("mood" => "sad")
    expect(event["transaction"]).to eq("Sidekiq/SadWorker")
    expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm sad!")
  end

  it "clears context after raising" do
    process_job("SadWorker")
    process_job("VerySadWorker")

    event = JSON.parse(Raven.client.transport.events.last[1])

    expect(event["tags"]).to eq("mood" => "very sad")
    expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm very sad!")
  end

  it "captures exceptions raised during events" do
    Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "Uhoh!" }]
    @processor.fire_event(:startup)

    event = JSON.parse(Raven.client.transport.events.last[1])

    expect(event["logentry"]["message"]).to eq "Uhoh!"
    expect(event["transaction"]).to eq "Sidekiq/startup"
  end

  it "has some context when capturing, even if no exception raised" do
    process_job("ReportingWorker")

    event = JSON.parse(Raven.client.transport.events.last[1])

    expect(event["logentry"]["message"]).to eq "I have something to say!"
    expect(event["extra"]["sidekiq"]).to eq("class" => "ReportingWorker", "queue" => "default")
  end
end
