# frozen_string_literal: true

# for https://github.com/getsentry/sentry-ruby/issues/1249
require "active_job/railtie"
# Rails 7.2 added HealthCheckController, which requires ActionController
require "action_controller/railtie"
require "active_support/all"
require "sentry/rails"
require "minitest/autorun"

class TestApp < Rails::Application
end

IO_STUB = StringIO.new

app = TestApp

# Simulate code from the application's init files in config/initializer
app.initializer :config_initializer do
  Rails.application.config.active_job.queue_name = "bobo"
end

# to simulate jobs being load during the eager_load initializer
app.initializer :eager_load! do
  Object.class_eval <<~CODE
    class ApplicationJob < ActiveJob::Base
      self.logger = Logger.new(IO_STUB)
      self.queue_adapter = :inline

      rescue_from Exception do |exception|
        logger.info(">>> RESCUED")
      end
    end

    class ErrorJob < ApplicationJob
      around_perform do |job, block|
        result = block.call
        logger.info(">>> I SHOULD NEVER BE EXECUTED!")
      end

      def perform
        1/0
      end
    end
  CODE
end

app.config.eager_load = true
app.initializer :sentry do
  Sentry.init do |config|
    config.logger = Logger.new(nil)
    config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
    config.background_worker_threads = 0
  end
end

app.initialize!

class ActiveJobExtensionsTest < ActiveSupport::TestCase
  def test_the_extension_is_loaded_before_eager_load_is_called
    ErrorJob.perform_later

    log_result = IO_STUB.string
    assert_match(/RESCUED/, log_result, "ApplicationJob's rescue_from should be called")
    refute_match(/I SHOULD NEVER BE EXECUTED/, log_result, "ErrorJob's around_perform should not be triggered")
  end

  def test_the_extension_doesnt_load_activejob_too_soon
    assert_equal("bobo", ApplicationJob.queue_name)
  end
end
