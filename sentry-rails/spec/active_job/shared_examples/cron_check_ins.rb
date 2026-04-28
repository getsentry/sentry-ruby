# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that emits cron check-ins for monitor jobs" do
  let(:cron_job) do
    job_fixture do
      include Sentry::Cron::MonitorCheckIns
      sentry_monitor_check_ins slug: "test-cron-ok-job"

      def perform
        "ok"
      end
    end
  end

  let(:failing_cron_job) do
    job_fixture do
      include Sentry::Cron::MonitorCheckIns
      sentry_monitor_check_ins(
        slug: "test-cron-fail-job",
        monitor_config: Sentry::Cron::MonitorConfig.from_crontab("5 * * * *")
      )

      def perform
        raise "boom from failing_cron_job spec"
      end
    end
  end

  it "emits in_progress and ok check-ins with correct slug for a successful job" do
    cron_job.perform_later
    drain

    check_ins = sentry_events.select { |e| e.is_a?(Sentry::CheckInEvent) }
    expect(check_ins.size).to eq(2)

    first, second = check_ins
    expect(first.to_h).to include(
      type: "check_in",
      status: :in_progress,
      monitor_slug: "test-cron-ok-job"
    )
    expect(second.to_h).to include(
      type: "check_in",
      status: :ok,
      check_in_id: first.check_in_id,
      monitor_slug: "test-cron-ok-job"
    )
    expect(second.to_h).to have_key(:duration)
  end

  it "returns the job's perform value through the cron mixin" do
    result = cron_job.perform_now
    expect(result).to eq("ok")
  end

  it "emits in_progress and error check-ins with monitor_config for a failing job" do
    expect do
      failing_cron_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_cron_job spec/)

    check_ins = sentry_events.select { |e| e.is_a?(Sentry::CheckInEvent) }
    error_events = sentry_events.select { |e| e.is_a?(Sentry::ErrorEvent) }

    expect(check_ins.map { |e| e.to_h[:status] }).to eq(%i[in_progress error])
    expect(check_ins.map { |e| e.to_h[:monitor_slug] }).to all(eq("test-cron-fail-job"))
    expect(check_ins.map { |e| e.to_h[:monitor_config] }).to all(include(
      schedule: { type: :crontab, value: "5 * * * *" }
    ))
    expect(error_events.size).to eq(1)
  end
end
