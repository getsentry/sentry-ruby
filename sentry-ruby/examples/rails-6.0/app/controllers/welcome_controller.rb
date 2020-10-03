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
      scope.set_user({id: 1, name: "Stan"})
      scope.set_transaction(request.env["PATH_INFO"])
      scope.set_tags({new_sdk: true, foo: "bar"})
    end
  end
end
