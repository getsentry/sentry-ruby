class WelcomeController < ApplicationController
  def index
    Rails.logger.info("zomg division")
    1 / 0
  end
  
  def report_demo
    @sentry_event_id = Raven.last_event_id
    render(:status => 500)
  end
end
