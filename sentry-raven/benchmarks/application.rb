require "active_support/all"
require "action_controller"
require_relative "../spec/support/test_rails_app/app"

def app(create = false)
  @app_integration_instance = nil if create
  @app_integration_instance ||= new_session do |sess|
    sess.host! "www.example.com"
  end
end

def new_session
  app = make_basic_app
  session = ActionDispatch::Integration::Session.new(app)
  yield session if block_given?

  # This makes app.url_for and app.foo_path available in the console
  session.extend(app.routes.url_helpers)
  session.extend(app.routes.mounted_helpers)

  session
end
