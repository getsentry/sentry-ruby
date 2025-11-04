# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/test_jobs"

RSpec.describe "without Sentry initialized", type: :job do
  it "runs job" do
    expect { FailedJob.perform_now }.to raise_error(FailedJob::TestError)
  end

  it "returns #perform method's return value" do
    expect(NormalJob.perform_now).to eq("foo")
  end
end

RSpec.describe "ActiveJob integration", type: :job do
  let(:event) do
    transport.events.last.to_json_compatible
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "returns #perform method's return value" do
    expect(NormalJob.perform_now).to eq("foo")
  end

  describe "ActiveJob arguments serialization" do
    before do
      make_basic_app
    end

    it "serializes ActiveRecord arguments in globalid form" do
      post = Post.create!
      post2 = Post.create!

      expect do
        JobWithArgument.perform_now("foo", { bar: Sentry }, integer: 1, post: post, nested: { another_level: { post: post2 } })
      end.to raise_error(RuntimeError)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible

      expect(event.dig("extra", "arguments")).to eq(
        [
          "foo",
          { "bar" => "Sentry" },
          {
            "integer" => 1,
            "post" => post.to_global_id.to_s,
            "nested" => { "another_level" => { "post" => post2.to_global_id.to_s } }
          }
        ]
      )
    end

    it "handles problematic globalid conversion gracefully" do
      post = Post.create!

      def post.to_global_id
        raise
      end

      expect do
        JobWithArgument.perform_now(integer: 1, post: post)
      end.to raise_error(RuntimeError)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible

      expect(event.dig("extra", "arguments")).to eq(
        [
          {
            "integer" => 1,
            "post" => post.to_s
          }
        ]
      )
    end

    it "serializes range arguments gracefully when Range#map is implemented" do
      post = Post.create!

      expect do
        JobWithArgument.perform_now("foo", { bar: Sentry }, integer: 1, post: post, range: 1..3)
      end.to raise_error(RuntimeError)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible

      expect(event.dig("extra", "arguments")).to eq(
        [
          "foo",
          { "bar" => "Sentry" },
          {
            "integer" => 1,
            "post" => post.to_global_id.to_s,
            "range" => [1, 2, 3]
          }
        ]
      )
    end

    it "serializes range arguments gracefully when Range consists of ActiveSupport::TimeWithZone" do
      post = Post.create!
      range = 5.days.ago...1.day.ago

      expect do
        JobWithArgument.perform_now("foo", { bar: Sentry }, integer: 1, post: post, range: range)
      end.to raise_error(RuntimeError)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible

      expect(event.dig("extra", "arguments")).to eq(
        [
          "foo",
          { "bar" => "Sentry" },
          {
            "integer" => 1,
            "post" => post.to_global_id.to_s,
            "range" => "#{range.first}...#{range.last}"
          }
        ]
      )
    end
  end

  describe "handling context" do
    before do
      make_basic_app
    end

    it "adds useful context to extra" do
      expect { FailedJob.perform_now }.to raise_error(FailedJob::TestError)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible

      expect(event.dig("extra", "active_job")).to eq("FailedJob")
      expect(event.dig("extra", "job_id")).to be_a(String)
      expect(event.dig("extra", "provider_job_id")).to be_nil
      expect(event.dig("extra", "arguments")).to eq([])

      expect(event.dig("tags", "job_id")).to eq(event.dig("extra", "job_id"))
      expect(event.dig("tags", "provider_job_id")).to eq(event.dig("extra", "provider_job_id"))
      last_frame = event.dig("exception", "values", 0, "stacktrace", "frames").last
      expect(last_frame["vars"]).to include({ "a" => "1", "b" => "0" })
    end

    it "clears context" do
      expect { FailedWithExtraJob.perform_now }.to raise_error(FailedWithExtraJob::TestError)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible

      expect(event["extra"]["foo"]).to eq("bar")

      expect(Sentry.get_current_scope.extra).to eq({})
    end
  end

  context "with tracing enabled" do
    before do
      make_basic_app do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "sends transaction" do
      QueryPostJob.perform_now

      expect(transport.events.size).to be(1)

      transaction = transport.events.last
      expect(transaction.transaction).to eq("QueryPostJob")
      expect(transaction.transaction_info).to eq({ source: :task })
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_present
      expect(transaction.contexts.dig(:trace, :span_id)).to be_present
      expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
      expect(transaction.contexts.dig(:trace, :op)).to eq("queue.active_job")
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")

      expect(transaction.spans.count).to eq(1)
      expect(transaction.spans.first[:op]).to eq("db.sql.active_record")
    end

    context "with error" do
      it "sends transaction and associates it with the event" do
        expect { FailedWithExtraJob.perform_now }.to raise_error(FailedWithExtraJob::TestError)

        expect(transport.events.size).to be(2)

        transaction = transport.events.first
        expect(transaction.transaction).to eq("FailedWithExtraJob")
        expect(transaction.transaction_info).to eq({ source: :task })
        expect(transaction.contexts.dig(:trace, :trace_id)).to be_present
        expect(transaction.contexts.dig(:trace, :span_id)).to be_present
        expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
        expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")

        event = transport.events.last
        expect(event.transaction).to eq("FailedWithExtraJob")
        expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))
      end
    end
  end

  context "when DeserializationError happens in user's jobs" do
    before do
      make_basic_app
    end

    class DeserializationErrorJob < ActiveJob::Base
      def perform
        1/0
      rescue
        raise ActiveJob::DeserializationError
      end
    end

    it "reports the root cause to Sentry" do
      expect do
        DeserializationErrorJob.perform_now
      end.to raise_error(ActiveJob::DeserializationError, /divided by 0/)

      expect(transport.events.size).to be(1)

      event = transport.events.last.to_json_compatible
      expect(event.dig("exception", "values", 0, "type")).to eq("ZeroDivisionError")
    end
  end

  context "using rescue_from" do
    before do
      make_basic_app
    end

    it 'does not trigger Sentry' do
      expect_any_instance_of(RescuedActiveJob).to receive(:rescue_callback).once.and_call_original

      expect { RescuedActiveJob.perform_now }.not_to raise_error

      expect(transport.events.size).to eq(0)
    end

    context "with exception in rescue_from" do
      it "reports both the original error and callback error" do
        expect_any_instance_of(ProblematicRescuedActiveJob).to receive(:rescue_callback).once.and_call_original

        expect { ProblematicRescuedActiveJob.perform_now }.to raise_error(RuntimeError)

        expect(transport.events.size).to eq(1)

        event = transport.events.first
        exceptions_data = event.exception.to_h[:values]

        expect(exceptions_data.count).to eq(2)
        expect(exceptions_data[0][:type]).to eq("FailedJob::TestError")
        expect(exceptions_data[1][:type]).to eq("RuntimeError")
      end
    end
  end

  context "when we are using an adapter which has a specific integration" do
    before do
      make_basic_app do |config|
        config.rails.skippable_job_adapters = ["ActiveJob::QueueAdapters::TestAdapter"]
      end
    end

    it "does not trigger sentry and re-raises" do
      expect { FailedJob.perform_now }.to raise_error(FailedJob::TestError)
      expect(transport.events.size).to eq(0)
    end
  end

  context "with cron monitoring mixin" do
    before do
      make_basic_app
    end

    context "normal job" do
      it "returns #perform method's return value" do
        expect(NormalJobWithCron.perform_now).to eq("foo")
      end

      it "captures two check ins" do
        NormalJobWithCron.perform_now

        expect(transport.events.size).to eq(2)

        first = transport.events[0]
        check_in_id = first.check_in_id
        expect(first).to be_a(Sentry::CheckInEvent)
        expect(first.to_h).to include(
          type: 'check_in',
          check_in_id: check_in_id,
          monitor_slug: "normaljobwithcron",
          status: :in_progress
        )

        second = transport.events[1]
        expect(second).to be_a(Sentry::CheckInEvent)
        expect(second.to_h).to include(
          :duration,
          type: 'check_in',
          check_in_id: check_in_id,
          monitor_slug: "normaljobwithcron",
          status: :ok
        )
      end
    end

    context "failed job" do
      it "captures two check ins" do
        expect { FailedJobWithCron.perform_now }.to raise_error(FailedJob::TestError)

        expect(transport.events.size).to eq(3)

        first = transport.events[0]
        check_in_id = first.check_in_id
        expect(first).to be_a(Sentry::CheckInEvent)
        expect(first.to_h).to include(
          type: 'check_in',
          check_in_id: check_in_id,
          monitor_slug: "failed_job",
          status: :in_progress,
          monitor_config: { schedule: { type: :crontab, value: "5 * * * *" } }
        )

        second = transport.events[1]
        expect(second).to be_a(Sentry::CheckInEvent)
        expect(second.to_h).to include(
          :duration,
          type: 'check_in',
          check_in_id: check_in_id,
          monitor_slug: "failed_job",
          status: :error,
          monitor_config: { schedule: { type: :crontab, value: "5 * * * *" } }
        )
      end
    end
  end

  describe "Reporting on retry errors", skip: RAILS_VERSION < 7.0 do
    before do
      if defined?(JRUBY_VERSION) && JRUBY_VERSION == "9.4.14.0"
        skip "This crashes on jruby + rails 7.0.0.x. See https://github.com/getsentry/sentry-ruby/issues/2612"
      end

      make_basic_app
    end

    context "when active_job_report_on_retry_error is true" do
      before do
        Sentry.configuration.rails.active_job_report_on_retry_error = true
      end

      after do
        Sentry.configuration.rails.active_job_report_on_retry_error = false
      end

      it "reports 3 exceptions" do
        allow(Sentry::Rails::ActiveJobExtensions::SentryReporter)
          .to receive(:capture_exception).and_call_original

        FailedJobWithRetryOn.perform_later rescue nil

        perform_enqueued_jobs
        perform_enqueued_jobs
        perform_enqueued_jobs rescue nil

        expect(Sentry::Rails::ActiveJobExtensions::SentryReporter)
          .to have_received(:capture_exception)
          .exactly(3).times
      end
    end

    context "when active_job_report_on_retry_error is false" do
      it "reports 1 exception on final attempt failure" do
        allow(Sentry::Rails::ActiveJobExtensions::SentryReporter)
          .to receive(:capture_exception).and_call_original

        FailedJobWithRetryOn.perform_later rescue nil

        perform_enqueued_jobs
        perform_enqueued_jobs
        perform_enqueued_jobs rescue nil

        expect(Sentry::Rails::ActiveJobExtensions::SentryReporter)
          .to have_received(:capture_exception)
          .exactly(1).times
      end
    end
  end
end
