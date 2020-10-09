class WelcomeController < ApplicationController
  before_action :set_sentry_context

  def index
    Rails.logger.info("zomg division")
    1 / 0
  rescue => e
    Sentry.capture_exception(e)
    raise e
  end

  def view_error
  end

  def report_demo
    # @sentry_event_id = Raven.last_event_id
    render(:status => 500)
  end

  private

  def set_sentry_context
    Sentry.configure_scope do |scope|
      scope.set_transaction_name(request.env["PATH_INFO"])
      counter = (scope.tags[:counter] || 0) + 1
      scope.set_tag(:counter, counter)
    end
  end
end
