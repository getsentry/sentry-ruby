class WelcomeController < ApplicationController
  before_action :set_sentry_context

  def index
    1 / 0
  end

  def view_error
  end

  def js_error
  end

  def worker_error
    ErrorWorker.perform_async
    render plain: "success"
  end

  def job_error
    ErrorJob.perform_later
    render plain: "success"
  end

  def report_demo
    # @sentry_event_id = Raven.last_event_id
    render(:status => 500)
  end

  private

  def set_sentry_context
    counter = (Sentry.get_current_scope.tags[:counter] || 0) + 1
    Sentry.set_tags(counter: counter)
  end
end
