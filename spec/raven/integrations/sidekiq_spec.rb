if RUBY_VERSION > '2.0'
  require 'spec_helper'

  require 'raven/integrations/sidekiq'
  require 'sidekiq/processor'

  RSpec.describe "Raven::SidekiqErrorHandler" do
    let(:context) do
      {
        "args" => [true, true],
        "class" => "HardWorker",
        "created_at" => 1_474_922_824.910579,
        "enqueued_at" => 1_474_922_824.910665,
        "error_class" => "RuntimeError",
        "error_message" => "a wild exception appeared",
        "failed_at" => 1_474_922_825.158953,
        "jid" => "701ed9cfa51c84a763d56bc4",
        "queue" => "default",
        "retry" => true,
        "retry_count" => 0
      }
    end

    it "should capture exceptions based on Sidekiq context" do
      exception = build_exception
      expected_options = {
        :message => exception.message,
        :extra => { :sidekiq => context }
      }

      expect(Raven).to receive(:capture_exception).with(exception, expected_options)

      Raven::SidekiqErrorHandler.new.call(exception, context)
    end

    context "when the captured exception is already annotated" do
      it "does a deep merge of options" do
        exception = build_exception
        Raven.annotate_exception(exception, :extra => { :job_title => "engineer" })
        expected_options = {
          :message => exception.message,
          :extra => {
            :sidekiq => context,
            :job_title => "engineer"
          }
        }

        expect(Raven::Event).to receive(:new).with(hash_including(expected_options))

        Raven::SidekiqErrorHandler.new.call(exception, context)
      end
    end

    it "filters out ActiveJob keys", :rails => true do
      exception = build_exception
      aj_context = context
      aj_context["_aj_globalid"] = GlobalID.new('gid://app/model/id')
      expected_context = aj_context.dup
      expected_context.delete("_aj_globalid")
      expected_context["_globalid"] = "gid://app/model/id"
      expected_options = {
        :message => exception.message,
        :extra => { :sidekiq => expected_context }
      }
      expect(Raven).to receive(:capture_exception).with(exception, expected_options)

      Raven::SidekiqErrorHandler.new.call(exception, aj_context)
    end
  end

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
    before(:all) do
      Sidekiq.error_handlers << Raven::SidekiqErrorHandler.new
      Sidekiq.server_middleware do |chain|
        chain.add Raven::SidekiqCleanupMiddleware
      end
      Sidekiq.logger = Logger.new(nil)
    end

    before do
      @mgr = double('manager')
      allow(@mgr).to receive(:options).and_return(:queues => ['default'])
      @processor = ::Sidekiq::Processor.new(@mgr)
    end

    def process_job(klass)
      msg = Sidekiq.dump_json("class" => klass)
      job = Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg)
      @processor.instance_variable_set(:'@job', job)

      @processor.send(:process, job)
    rescue # rubocop:disable Lint/HandleExceptions
      # do nothing
    end

    it "actually captures an exception" do
      redis_on = Sidekiq.redis(&:info) rescue nil
      skip("No Redis server online") unless redis_on

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
end
