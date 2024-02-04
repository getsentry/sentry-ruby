class WelcomeController < ApplicationController
  before_action :set_sentry_context

  def index
    a = 1
    b = 0
    a / b
  end

  def connect_trace
    # see the sinatra example under the `sentry-ruby` folder
    response = Net::HTTP.get_response(URI("http://localhost:4567/connect_trace"))

    render plain: response.code
  end

  def appearance
  end

  def view_error
  end

  def sidekiq_error
    ErrorWorker.perform_async
    render plain: "Remember to start sidekiq worker with '$ bundle exec sidekiq'"
  end

  def resque_error
    Resque.enqueue(RaiseError)
    render plain: "Remember to start resque worker with '$ QUEUE=* bundle exec rake resque:work'"
  end

  def delayed_job_error
    ErrorDelayedJob.delay.perform
    render plain: "Remember to start delayed_job worker with '$ bundle exec rake jobs:work'"
  end

  def job_error
    ErrorJob.perform_later
    render plain: "success"
  end

  def report_demo
    # @sentry_event_id = Raven.last_event_id
    render(status: 500)
  end

  private

  def set_sentry_context
    counter = (Sentry.get_current_scope.tags[:counter] || 0) + 1
    Sentry.set_tags(counter: counter)
  end
end
