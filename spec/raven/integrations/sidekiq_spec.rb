if RUBY_VERSION > '2.0'
  require 'spec_helper'

  require 'raven/integrations/sidekiq'
  require 'sidekiq/processor'

  describe "Raven::SidekiqErrorHandler" do
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
        :extra => { :sidekiq => context },
        :culprit => "Sidekiq/HardWorker"
      }

      expect(Raven).to receive(:capture_exception).with(exception, expected_options)

      Raven::SidekiqErrorHandler.new.call(exception, context)
    end

    it "filters out ActiveJob keys" do
      exception = build_exception
      aj_context = context
      aj_context["_aj_globalid"] = "oh noes"
      expected_context = aj_context
      expected_context.delete("_aj_globalid")
      expected_context["_globalid"] = "oh noes"
      expected_options = {
        :message => exception.message,
        :extra => { :sidekiq => expected_context },
        :culprit => "Sidekiq/HardWorker"
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

  describe "Sidekiq full-stack integration" do
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
      expect { process_job("SadWorker") }.to change { Raven.client.transport.events.size }.by(1)
    end

    it "clears context from other workers and captures its own" do
      process_job("HappyWorker")
      process_job("SadWorker")

      event = JSON.parse(Raven.client.transport.events.last[1])

      expect(event["tags"]).to eq("mood" => "sad")
      expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm sad!")
    end

    it "clears context after raising" do
      process_job("SadWorker")
      process_job("VerySadWorker")

      event = JSON.parse(Raven.client.transport.events.last[1])

      expect(event["tags"]).to eq("mood" => "very sad")
      expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm very sad!")
    end
  end
end
