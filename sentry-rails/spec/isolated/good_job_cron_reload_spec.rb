# frozen_string_literal: true

begin
  require "good_job"
rescue LoadError
end

if defined?(::GoodJob)
  RSpec.describe "GoodJob cron monitoring across Rails reloads" do
    it "continues monitoring after Rails replaces CronEntry" do
      app = Sentry::Rails::Test::Application.define do |application|
        application.config.cache_classes = false
        application.config.eager_load = false
        application.initializer :configure_sentry do
          Sentry.init do |config|
            config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
            config.transport.transport_class = Sentry::DummyTransport
            config.background_worker_threads = 0
            config.enabled_patches << :good_job_cron
          end
        end
      end

      old_entry_class = GoodJob::CronEntry
      app.reloader.reload!
      expect(GoodJob::CronEntry).not_to equal(old_entry_class)

      GoodJob.configuration = GoodJob::Configuration.new({ cron: { report: { class: "ActiveJob::Base", cron: "0 9 * * *" } } })
      record = Struct.new(:cron_key, :job_class).new("report", "ActiveJob::Base")
      ActiveSupport::Notifications.instrument("perform_job.good_job", job: record) { }

      check_ins = sentry_events.grep(Sentry::CheckInEvent)
      expect(check_ins.map(&:status)).to eq([:in_progress, :ok])
      expect(check_ins.map(&:monitor_slug)).to eq(["report", "report"])
    end
  end
end
