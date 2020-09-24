class ApplicationController < ActionController::Base
  before_action :set_raven_context

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  private

  def set_raven_context
    # Raven.user_context(email: 'david@getsentry.com')
    # Raven.extra_context(params: params.to_hash, url: request.url)
  end
end
