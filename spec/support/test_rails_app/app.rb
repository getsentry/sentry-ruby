require 'rails'
# require "active_record/railtie"
require "action_view/railtie"
require "action_controller/railtie"
# require "action_mailer/railtie"
require "active_job/railtie"
# require "action_cable/engine"
# require "sprockets/railtie"
# require "rails/test_unit/railtie"
require 'raven/integrations/rails'

ActiveSupport::Deprecation.silenced = true

class TestApp < Rails::Application
  config.secret_key_base = "test"

  # Usually set for us in production.rb
  config.eager_load = true

  routes.append do
    get "/exception", :to => "hello#exception"
    root :to => "hello#world"
  end

  initializer :configure_release do
    Raven.configure do |config|
      config.release = 'beta'
    end
  end
end

class HelloController < ActionController::Base
  def exception
    raise "An unhandled exception!"
  end

  def world
    render :plain => "Hello World!"
  end
end
