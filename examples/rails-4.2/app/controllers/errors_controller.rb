class ErrorsController < ApplicationController
  def internal_server_error
    @sentry_event_id = Raven.last_event_id
    render(:status => 500)
  end
end
