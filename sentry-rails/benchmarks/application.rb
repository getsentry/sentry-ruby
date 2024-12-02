# frozen_string_literal: true

require "active_support/all"
require "action_controller"
require_relative "../spec/support/test_rails_app/app"

def create_app(&block)
  app = make_basic_app(&block)

  session = ActionDispatch::Integration::Session.new(app)
  session.host! "www.example.com"
  session.extend(app.routes.url_helpers)
  session.extend(app.routes.mounted_helpers)
end
