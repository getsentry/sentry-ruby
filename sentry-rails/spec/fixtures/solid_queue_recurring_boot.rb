# frozen_string_literal: true

require "logger"
require "tmpdir"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "solid_queue"
require "sentry-ruby"
require "sentry-rails"

LOADED_BEFORE_INITIALIZATION = []

[:active_record, :active_job].each do |name|
  ActiveSupport.on_load(name) do
    LOADED_BEFORE_INITIALIZATION << name unless Rails.application.initialized?
  end
end

class SolidQueueBootApp < Rails::Application
  config.root = Dir.mktmpdir
  config.eager_load = ENV["EAGER_LOAD"] == "true"
  config.enable_reloading = !config.eager_load
  config.logger = Logger.new(nil)
  config.active_support.to_time_preserves_timezone = :zone

  initializer :sentry do
    Sentry.init do |sentry|
      sentry.dsn = "http://12345:67890@sentry.localdomain/sentry/42"
      sentry.sdk_logger = Logger.new(nil)
      sentry.enabled_patches << :solid_queue_recurring
    end
  end
end

SolidQueueBootApp.initialize!

if !SolidQueueBootApp.config.eager_load && LOADED_BEFORE_INITIALIZATION.any?
  abort "Loaded before initialization: #{LOADED_BEFORE_INITIALIZATION.join(", ")}"
end

patch = Sentry::Rails::SolidQueueRecurring::RecurringTask
abort "RecurringTask is not patched" unless SolidQueue::RecurringTask < patch

unless SolidQueueBootApp.config.eager_load
  original = SolidQueue::RecurringTask
  Rails.application.reloader.reload!

  abort "RecurringTask was not reloaded" if SolidQueue::RecurringTask.equal?(original)
  abort "RecurringTask is not patched after a reload" unless SolidQueue::RecurringTask < patch
end
