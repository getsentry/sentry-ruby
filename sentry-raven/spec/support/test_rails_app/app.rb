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
end

class HelloController < ActionController::Base
  def exception
    raise "An unhandled exception!"
  end

  def view_exception
    render inline: "<%= foo %>"
  end

  def world
    render :plain => "Hello World!"
  end
end

def make_basic_app
  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.hosts = nil
  app.config.secret_key_base = "test"

  # Usually set for us in production.rb
  app.config.eager_load = true
  app.routes.append do
    get "/exception", :to => "hello#exception"
    get "/view_exception", :to => "hello#view_exception"
    root :to => "hello#world"
  end

  app.initializer :configure_release do
    Raven.configure do |config|
      config.release = 'beta'
    end
  end

  app.initialize!

  Rails.application = app
  app
end
