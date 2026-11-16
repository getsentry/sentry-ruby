# frozen_string_literal: true

require "good_job"

RSpec.describe "Enabling GoodJob cron monitoring during Rails boot" do
  it "registers its subscriber without loading CronEntry during Sentry.init" do
    expect(Sentry::Rails::GoodJobCron).to receive(:patch).and_wrap_original do |original|
      expect($LOADED_FEATURES.grep(%r{/good_job/cron_entry\.rb\z})).to be_empty
      original.call
      expect($LOADED_FEATURES.grep(%r{/good_job/cron_entry\.rb\z})).to be_empty
    end

    make_basic_app do |config|
      config.enabled_patches << :good_job_cron
    end

    expect(Sentry).to be_initialized
  end
end
