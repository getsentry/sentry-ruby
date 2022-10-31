require "spec_helper"

RSpec.describe Sentry::DelayedJob do
  before do
    perform_basic_setup
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  class Post
    def raise_error
      1 / 0
    end

    def tagged_error(number: 1)
      Sentry.set_tags(number: number)
      raise
    end

    def tagged_report(number: 1)
      Sentry.set_tags(number: number)
      Sentry.capture_message("tagged report")
    end

    def report
      Sentry.capture_message("report")
    end

    def do_nothing
    end

    def self.class_do_nothing
    end
  end

  it "sets correct extra/tags context for each job" do
    Post.new.delay.report
    enqueued_job = Delayed::Backend::ActiveRecord::Job.last
    enqueued_job.invoke_job

    expect(transport.events.count).to eq(1)
    event = transport.events.last.to_hash
    expect(event[:message]).to eq("report")
    expect(event[:contexts][:"Delayed-Job"][:id]).to eq(enqueued_job.id.to_s)
    expect(event[:tags]).to eq({ "delayed_job.id" => enqueued_job.id.to_s, "delayed_job.queue" => nil })
  end

  it "doesn't leak scope data outside of the job" do
    Post.new.delay.report
    enqueued_job = Delayed::Backend::ActiveRecord::Job.last
    enqueued_job.invoke_job

    expect(transport.events.count).to eq(1)
    expect(Sentry.get_current_scope.extra).to eq({})
    expect(Sentry.get_current_scope.tags).to eq({})
  end

  it "doesn't share scope data between jobs" do
    Post.new.delay.tagged_report
    enqueued_job = Delayed::Backend::ActiveRecord::Job.last
    enqueued_job.invoke_job

    expect(transport.events.count).to eq(1)
    event = transport.events.last.to_hash
    expect(event[:message]).to eq("tagged report")
    expect(event[:tags]).to eq({ "delayed_job.id" => enqueued_job.id.to_s, "delayed_job.queue" => nil, number: 1 })

    Post.new.delay.report
    enqueued_job = Delayed::Backend::ActiveRecord::Job.last
    enqueued_job.invoke_job

    expect(transport.events.count).to eq(2)
    event = transport.events.last.to_hash
    expect(event[:tags]).to eq({ "delayed_job.id" => enqueued_job.id.to_s, "delayed_job.queue" => nil })
  end

  context "when a job failed" do
    let(:enqueued_job) do
      Post.new.delay.raise_error
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last
    end

    it "reports exception" do
      expect do
        enqueued_job.invoke_job
      end.to raise_error(ZeroDivisionError)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_hash

      expect(event[:sdk]).to eq({ name: "sentry.ruby.delayed_job", version: described_class::VERSION })
      expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
      expect(event[:tags]).to eq({ "delayed_job.id" => enqueued_job.id.to_s, "delayed_job.queue" => nil })
    end

    it "doesn't leak scope data" do
      Post.new.delay.tagged_error
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last

      expect do
        enqueued_job.invoke_job
      end.to raise_error(RuntimeError)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_hash

      expect(event[:tags]).to eq({ "delayed_job.id" => enqueued_job.id.to_s, "delayed_job.queue" => nil, number: 1 })
      expect(Sentry.get_current_scope.extra).to eq({})
      expect(Sentry.get_current_scope.tags).to eq({})

      Post.new.delay.raise_error
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last

      expect do
        enqueued_job.invoke_job
      end.to raise_error(ZeroDivisionError)

      expect(transport.events.count).to eq(2)
      event = transport.events.last.to_hash
      expect(event[:tags]).to eq({ "delayed_job.id" => enqueued_job.id.to_s, "delayed_job.queue" => nil })
      expect(Sentry.get_current_scope.extra).to eq({})
      expect(Sentry.get_current_scope.tags).to eq({})
    end

    context "with report_after_job_retries set to true" do
      before do
        Sentry.configuration.delayed_job.report_after_job_retries = true
      end

      after do
        Sentry.configuration.delayed_job.report_after_job_retries = false
      end

      it "reports exception after the last retry" do
        enqueued_job.update(attempts: Delayed::Worker.max_attempts.succ)

        expect do
          enqueued_job.invoke_job
        end.to raise_error(ZeroDivisionError)

        expect(transport.events.count).to eq(1)
      end

      it "skips report if not on the last retry" do
        enqueued_job.update(attempts: 0)

        expect do
          enqueued_job.invoke_job
        end.to raise_error(ZeroDivisionError)

        expect(transport.events.count).to eq(0)
      end
    end
  end

  context "with ActiveJob" do
    require "rails"
    require "active_job"
    require "sentry-rails"

    class ReportingJob < ActiveJob::Base
      self.queue_adapter = :delayed_job

      def perform
        Sentry.set_tags(number: 1)
        Sentry.capture_message("report from ActiveJob")
      end
    end

    class FailedJob < ActiveJob::Base
      self.queue_adapter = :delayed_job

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
        Sentry.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::DelayedJobAdapter"
      end
    end

    context "when the job succeeded" do
      before do
        ReportingJob.perform_later

        enqueued_job = Delayed::Backend::ActiveRecord::Job.last
        enqueued_job.invoke_job
      end

      it "doesn't leak scope data" do
        expect(transport.events.count).to eq(1)

        expect(Sentry.get_current_scope.tags).to eq({})
      end

      it "injects ActiveJob information to the event" do
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_hash
        expect(event[:message]).to eq("report from ActiveJob")
        expect(event[:tags]).to match({ "delayed_job.id" => anything, "delayed_job.queue" => "default", number: 1 })
        expect(event[:contexts][:"Active-Job"][:job_class]).to eq("ReportingJob")
      end
    end

    context "when the job failed" do
      before do
        FailedJob.perform_later

        enqueued_job = Delayed::Backend::ActiveRecord::Job.last

        expect do
          enqueued_job.invoke_job
        end.to raise_error(ZeroDivisionError)
      end

      it "doesn't duplicate error reporting" do
        expect(transport.events.count).to eq(1)

        expect(Sentry.get_current_scope.tags).to eq({})
      end

      it "injects ActiveJob information to the event" do
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_hash
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
        expect(event[:tags]).to match({ "delayed_job.id" => anything, "delayed_job.queue" => "default", number: 2 })
        expect(event[:contexts][:"Active-Job"][:job_class]).to eq("FailedJob")
      end
    end

    context "when tracing is enabled" do
      before do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::DelayedJobAdapter"
        end
      end

      it "records transaction" do
        ReportingJob.perform_later

        enqueued_job = Delayed::Backend::ActiveRecord::Job.last
        enqueued_job.invoke_job

        expect(transport.events.count).to eq(2)
        transaction = transport.events.last

        expect(transaction.transaction).to eq("ReportingJob")
        expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
        expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
      end

      it "records transaction with exception" do
        FailedJob.perform_later
        enqueued_job = Delayed::Backend::ActiveRecord::Job.last
        begin
          enqueued_job.invoke_job
        rescue ZeroDivisionError
          nil
        end

        expect(transport.events.count).to eq(2)
        transaction = transport.events.last

        expect(transaction.transaction).to eq("FailedJob")
        expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
        expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
        expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")

        event = transport.events.last
        expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))
      end
    end
  end

  context ".compute_job_class" do
    it 'returns the class and method name for a delayed instance method call' do
      Post.new.delay.do_nothing
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last

      expect(Sentry::DelayedJob::Plugin.compute_job_class(enqueued_job.payload_object)).to eq("Post#do_nothing")
    end

    it 'returns the class and method name for a delayed class method call' do
      Post.delay.class_do_nothing
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last

      expect(Sentry::DelayedJob::Plugin.compute_job_class(enqueued_job.payload_object)).to eq("Post#class_do_nothing")
    end

    it 'returns the class name for anything else' do

      expect(Sentry::DelayedJob::Plugin.compute_job_class("something")).to eq("String")
      expect(Sentry::DelayedJob::Plugin.compute_job_class(Sentry::DelayedJob::Plugin)).to eq("Class")
    end
  end

  context "when tracing is enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "records transaction" do
      Post.new.delay.do_nothing
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last
      enqueued_job.invoke_job

      expect(transport.events.count).to eq(1)
      transaction = transport.events.last

      expect(transaction.transaction).to eq("Post#do_nothing")
      expect(transaction.transaction_info).to eq({ source: :task })
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
      expect(transaction.contexts.dig(:trace, :op)).to eq("queue.delayed_job")
    end

    it "records transaction with exception" do
      Post.new.delay.raise_error
      enqueued_job = Delayed::Backend::ActiveRecord::Job.last
      begin
        enqueued_job.invoke_job
      rescue ZeroDivisionError
        nil
      end

      expect(transport.events.count).to eq(2)
      transaction = transport.events.last

      expect(transaction.transaction).to eq("Post#raise_error")
      expect(transaction.transaction_info).to eq({ source: :task })
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")

      event = transport.events.last
      expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))
    end
  end
end


RSpec.describe Sentry::DelayedJob, "not initialized" do
  class Thing
    def self.invoked_method; end
  end

  it "doesn't swallow jobs" do
    expect(Thing).to receive(:invoked_method)
    Delayed::Job.delete_all
    expect(Delayed::Job.count).to eq(0)

    Thing.delay.invoked_method
    expect(Delayed::Job.count).to eq(1)

    Delayed::Worker.new.run(Delayed::Job.last)
    expect(Delayed::Job.count).to eq(0)
  end
end
