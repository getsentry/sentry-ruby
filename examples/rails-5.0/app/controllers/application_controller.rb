class ApplicationController < ActionController::Base
  before_action :set_raven_context
  protect_from_forgery with: :exception

  private

  def set_raven_context
    # Raven.user_context(email: 'david@getsentry.com')
    # Raven.extra_context(params: params.to_hash, url: request.url)
  end
end
