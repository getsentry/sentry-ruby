# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "BackgroundWorker"
rescue LoadError
end

require "shellwords"

# The connection patch is applied at most once per process, so each case boots a
# bare app in a child process.
RSpec.describe "Sentry::BackgroundWorker ActiveRecord connection patch" do
  def boot_app_and_run_job(active_record_requires)
    script = <<~RUBY
      require "action_controller/railtie"
      #{active_record_requires}
      require "sentry-rails"

      class BackgroundWorkerApp < Rails::Application
        config.eager_load = false
        config.secret_key_base = "secret"
      end

      log = StringIO.new

      BackgroundWorkerApp.initializer :sentry do
        Sentry.init do |config|
          config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
          config.sdk_logger = Logger.new(log)
          config.background_worker_threads = 0
        end
      end

      BackgroundWorkerApp.initialize!

      ran = false
      Sentry.background_worker.perform { ran = true }

      patched = defined?(Sentry::BackgroundWorker::ActiveRecordConnectionPatch) &&
        Sentry::BackgroundWorker.ancestors.include?(Sentry::BackgroundWorker::ActiveRecordConnectionPatch)

      print [patched ? "patched" : "unpatched", ran ? "ran" : "skipped", log.string.include?("exception happened in background worker") ? "error" : "no-error"].join(",")
    RUBY

    `#{RbConfig.ruby} -e #{Shellwords.escape(script)}`.lines.last
  end

  it "is applied when ActiveRecord is fully loaded" do
    expect(boot_app_and_run_job(%(require "active_record/railtie"))).to eq("patched,ran,no-error")
  end

  it "is skipped when only part of ActiveRecord is loaded" do
    expect(boot_app_and_run_job(%(require "active_model"; require "active_record/errors"))).to eq("unpatched,ran,no-error")
  end
end
