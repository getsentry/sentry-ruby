# frozen_string_literal: true

class HelloController < ActionController::Base
  protect_from_forgery with: :exception

  def exception
    raise "An unhandled exception!"
  end

  def reporting
    render plain: Sentry.last_event_id
  end

  def view_exception
    render inline: "<%= foo %>"
  end

  def view
    render template: "test_template"
  end

  def world
    render plain: "Hello World!"
  end

  def with_custom_instrumentation
    custom_event = "custom.instrument"
    ActiveSupport::Notifications.subscribe(custom_event) do |*args|
      data = args[-1]
      data += 1
    end

    ActiveSupport::Notifications.instrument(custom_event, 1)

    head :ok
  end

  def not_found
    raise ActionController::BadRequest
  end
end
