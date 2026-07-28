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
      arguments: [],
      job_id: a_kind_of(String)
    )
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

  context "with Rails.error.set_context data attached before the job raises", skip: RAILS_VERSION < 7.0 do
    def capture_job_error_with_context(context)
      job_with_context = job_fixture do
        define_method(:perform) do
          Rails.error.set_context(**context)
          raise "boom with rails error context"
        end
      end

      expect do
        job_with_context.perform_later
        drain
      end.to raise_error(RuntimeError, /boom with rails error context/)

      last_sentry_event
    end

    it "attaches the context to the captured event" do
      event = capture_job_error_with_context(
        debug_key: "important_value",
        timestamp: Time.utc(2026, 7, 21, 12, 34, 56),
        zoned_timestamp: ActiveSupport::TimeZone["Eastern Time (US & Canada)"].parse("2026-07-21 12:34:56"),
        date: Date.new(2026, 7, 21)
      )

      expect(event.contexts).to include(
        "rails.error" => hash_including(
          debug_key: "important_value",
          timestamp: Time.utc(2026, 7, 21, 12, 34, 56),
          zoned_timestamp: ActiveSupport::TimeZone["Eastern Time (US & Canada)"].parse("2026-07-21 12:34:56"),
          date: Date.new(2026, 7, 21)
        )
      )
    end

    it "redacts values matching config.filter_parameters" do
      event = capture_job_error_with_context(
        api_key: "secret-api-key",
        nested: { password: "hunter2", safe: "kept" }
      )

      expect(event.contexts).to include(
        "rails.error" => hash_including(
          api_key: "[FILTERED]",
          nested: { password: "[FILTERED]", safe: "kept" }
        )
      )
    end

    it "redacts sensitive values inside non-Hash Enumerables" do
      event = capture_job_error_with_context(records: Set[{ password: "hunter2" }])

      expect(event.contexts).to include(
        "rails.error" => hash_including(records: [{ password: "[FILTERED]" }])
      )
    end

    it "does not expand the job instance into the context" do
      event = capture_job_error_with_context(debug_key: "important_value")

      job = event.to_json_compatible.dig("contexts", "rails.error", "job")

      expect(job).to be_a(String)
      expect(job).to match(/#<JobFixture/)
    end
  end
end
