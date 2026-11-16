# frozen_string_literal: true

require "good_job"

RSpec.describe "Enabling the :good_job_cron patch with a GoodJob older than 4.0" do
  let(:sdk_log) { StringIO.new }

  before { stub_const("GoodJob::VERSION", "3.99.0") }

  it "boots the app, logs a warning, and sends no check-ins" do
    make_basic_app do |config|
      config.enabled_patches << :good_job_cron
      config.sdk_logger = Logger.new(sdk_log)
    end

    GoodJob.configuration = GoodJob::Configuration.new({ cron: { report: { class: "ActiveJob::Base", cron: "0 9 * * *" } } })
    record = Struct.new(:cron_key, :job_class).new("report", "ActiveJob::Base")
    ActiveSupport::Notifications.instrument("perform_job.good_job", job: record) { }

    expect(Sentry).to be_initialized
    expect(sdk_log.string).to include("The GoodJob cron integration requires good_job 4.0 or later, but 3.99.0 is installed.")
    expect(sentry_events.grep(Sentry::CheckInEvent)).to be_empty
  end
end
