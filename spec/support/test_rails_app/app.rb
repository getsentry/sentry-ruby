require 'rails'
# require "active_model/railtie"
# require "active_job/railtie"
# require "active_record/railtie"
require "action_controller/railtie"
# require "action_mailer/railtie"
require "action_view/railtie"
# require "action_cable/engine"
# require "sprockets/railtie"
# require "rails/test_unit/railtie"
require 'raven/integrations/rails'

class TestApp < Rails::Application
  config.secret_key_base = "test"

  # Usually set for us in production.rb
  config.eager_load = true
  config.cache_classes = true
  config.serve_static_files = false

  config.log_level = :error
  config.logger = Logger.new(STDOUT)

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
    render :text => "Hello World!"
  end
end

Rails.env = "production"
