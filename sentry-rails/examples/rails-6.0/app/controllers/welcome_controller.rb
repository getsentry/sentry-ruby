class WelcomeController < ApplicationController
  before_action :set_sentry_context

  def index
    1 / 0
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
      counter = (scope.tags[:counter] || 0) + 1
      scope.set_tag(:counter, counter)
    end
  end
end
