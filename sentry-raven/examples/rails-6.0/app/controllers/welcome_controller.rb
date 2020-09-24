class WelcomeController < ApplicationController
  before_action :set_raven_context

  def index
    Rails.logger.info("zomg division")
    1 / 0
  end

  def view_error
  end

  def report_demo
    @sentry_event_id = Raven.last_event_id
    render(:status => 500)
  end

  private

  def set_raven_context
    Raven.user_context(id: "fake-user-id") # or anything else in session
    Raven.extra_context(params: params.to_unsafe_h, url: request.url, info: "extra info")
  end
end
