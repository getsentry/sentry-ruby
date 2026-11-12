# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "GoodJobCronWithoutGoodJob"
rescue LoadError
end

RSpec.describe "Enabling the :good_job_cron patch without the good_job gem" do
  let(:sdk_log) { StringIO.new }

  it "boots the app and logs a warning" do
    expect(defined?(::GoodJob)).to be_nil

    make_basic_app do |config|
      config.enabled_patches << :good_job_cron
      config.sdk_logger = Logger.new(sdk_log)
    end

    expect(Sentry).to be_initialized
    expect(sdk_log.string).to include("You tried to enable the GoodJob cron integration but the `good_job` gem was not detected.")
  end
end
