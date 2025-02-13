# frozen_string_literal: true

require "active_job/railtie"

class NormalJob < ActiveJob::Base
  def perform
    "foo"
  end
end

class FailedJob < ActiveJob::Base
  self.logger = nil

  class TestError < RuntimeError
  end

  def perform
    a = 1
    b = 0
    raise TestError, "Boom!"
  end
end

class FailedWithExtraJob < FailedJob
  def perform
    Sentry.get_current_scope.set_extras(foo: :bar)
    super
  end
end

class JobWithArgument < ActiveJob::Base
  def perform(*args, integer:, post:, **options)
    raise "foo"
  end
end

class QueryPostJob < ActiveJob::Base
  self.logger = nil

  def perform
    Post.all.to_a
  end
end

class RescuedActiveJob < FailedWithExtraJob
  rescue_from TestError, with: :rescue_callback

  def rescue_callback(error); end
end

class ProblematicRescuedActiveJob < FailedWithExtraJob
  rescue_from TestError, with: :rescue_callback

  def rescue_callback(error)
    raise "foo"
  end
end

class NormalJobWithCron < NormalJob
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins
end

class FailedJobWithCron < FailedJob
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins slug: "failed_job", monitor_config: Sentry::Cron::MonitorConfig.from_crontab("5 * * * *")
end
