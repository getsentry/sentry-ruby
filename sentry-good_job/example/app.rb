# frozen_string_literal: true

require "bundler/setup"
require "sentry-good_job"
require "active_job"
require "good_job"

# Configure Sentry
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"] || "http://12345:67890@sentry.localdomain/sentry/42"
  config.environment = "development"
  config.logger = Logger.new(STDOUT)

  # Good Job specific configuration
  config.good_job.report_after_job_retries = false
  config.good_job.include_job_arguments = true
  config.good_job.logging_enabled = true
end

# Example job classes
class HappyJob < ActiveJob::Base
  def perform(message)
    puts "Happy job executed with message: #{message}"
    Sentry.add_breadcrumb(message: "Happy job completed successfully")
  end
end

class SadJob < ActiveJob::Base
  def perform(message)
    puts "Sad job executed with message: #{message}"
    raise "Something went wrong in the sad job!"
  end
end

class ScheduledJob < ActiveJob::Base
  def perform
    puts "Scheduled job executed at #{Time.now}"
  end
end

# Example usage
puts "Sentry Good Job Integration Example"
puts "=================================="

# Enqueue some jobs
HappyJob.perform_later("Hello from happy job!")
SadJob.perform_later("Hello from sad job!")

puts "\nJobs enqueued. Check your Sentry dashboard for error reports."
puts "The sad job will generate an error that should be captured by Sentry."
