# frozen_string_literal: true

module Sentry
  class Configuration
    attr_reader :good_job

    add_post_initialization_callback do
      @good_job = Sentry::GoodJob::Configuration.new
      @excluded_exceptions = @excluded_exceptions.concat(Sentry::GoodJob::IGNORE_DEFAULT)
    end
  end

  module GoodJob
    IGNORE_DEFAULT = [
      "ActiveJob::DeserializationError",
      "ActiveJob::SerializationError"
    ]

    class Configuration
      # Whether to enable cron monitoring for all scheduled jobs
      # This is GoodJob-specific functionality for monitoring scheduled tasks
      attr_accessor :enable_cron_monitors

      def initialize
        @enable_cron_monitors = true
      end
    end
  end
end
