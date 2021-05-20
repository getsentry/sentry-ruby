class WelcomeController < ApplicationController
  before_action :set_sentry_context

  def index
    1 / 0
  end

  def connect_trace
    transaction = Sentry.get_current_scope.get_transaction
    # see the sinatra example under the `sentry-ruby` folder
    response = Net::HTTP.get_response(URI("http://localhost:4567/connect_trace"))

    render plain: response.code
  end

  def view_error
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
