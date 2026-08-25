# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that attaches job context to error events" do
  let(:failing_job) do
    job_fixture do
      def perform
        a = 1
        b = 0
        raise "boom from failing_job spec"
      end
    end
  end

  it "attaches job context to extras and tags on the captured event" do
    expect do
      failing_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    event = last_sentry_event

    expect(event.extra).to include(
      active_job: failing_job.name,
      job_id: a_kind_of(String)
    )
    expect(event.extra).not_to have_key(:arguments)
    expect(event.extra).to have_key(:provider_job_id)
    expect(event.extra).to have_key(:locale)
    expect(event.extra).to have_key(:scheduled_at)

    expect(event.tags).to include(
      job_id: event.extra[:job_id],
      provider_job_id: event.extra[:provider_job_id]
    )

    last_frame = event.exception.values.first.stacktrace.frames.last
    expect(last_frame.vars).to include(a: "1", b: "0")
  end

  context "when queue data collection is enabled" do
    let(:configure_sentry) do
      proc do |config|
        config.data_collection.queues = true
      end
    end

    it "includes job arguments in the captured event" do
      job = job_fixture do
        def perform(_argument)
          raise "boom from job with arguments"
        end
      end

      expect do
        job.perform_later("sensitive argument")
        drain
      end.to raise_error(RuntimeError, /boom from job with arguments/)

      expect(last_sentry_event.extra[:arguments]).to eq(["sensitive argument"])
    end
  end

  context "with Rails.error.set_context data attached before the job raises", skip: RAILS_VERSION < 7.0 do
    let(:job_with_context) do
      job_fixture do
        def perform
          Rails.error.set_context(
            debug_key: "important_value",
            timestamp: Time.utc(2026, 7, 21, 12, 34, 56),
            zoned_timestamp: ActiveSupport::TimeZone["Eastern Time (US & Canada)"].parse("2026-07-21 12:34:56"),
            date: Date.new(2026, 7, 21)
          )
          raise "boom with rails error context"
        end
      end
    end

    def capture_job_error
      expect do
        job_with_context.perform_later
        drain
      end.to raise_error(RuntimeError, /boom with rails error context/)

      last_sentry_event
    end

    it "omits the context from the captured event when queue data collection is disabled" do
      expect(capture_job_error.contexts).not_to have_key("rails.error")
    end

    context "when queue data collection is enabled" do
      let(:configure_sentry) do
        proc do |config|
          config.data_collection.queues = true
        end
      end

      it "includes the context in the captured event" do
        expect(capture_job_error.contexts).to include(
          "rails.error" => hash_including(
            debug_key: "important_value",
            timestamp: Time.utc(2026, 7, 21, 12, 34, 56),
            zoned_timestamp: ActiveSupport::TimeZone["Eastern Time (US & Canada)"].parse("2026-07-21 12:34:56"),
            date: Date.new(2026, 7, 21)
          )
        )
      end
    end
  end
end
