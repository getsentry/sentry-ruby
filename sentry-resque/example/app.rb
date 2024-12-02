# frozen_string_literal: true

require "active_job"
require "resque"
require "sentry-resque"

Sentry.init do |config|
  config.breadcrumbs_logger = [:sentry_logger]
  # replace it with your sentry dsn
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
end

class MyJob < ActiveJob::Base
  self.queue_adapter = :resque

  def perform
    raise "foo"
  end
end

worker = Resque::Worker.new(:default)

MyJob.perform_later

begin
  worker.work(0)
rescue => e
  puts("active job failed because of \"#{e.message}\"")
end

class Foo
  def self.perform
    1 / 0
  end
end

Resque::Job.create(:default, Foo)

begin
  worker.work(0)
rescue => e
  puts("inline job failed because of \"#{e.message}\"")
end
