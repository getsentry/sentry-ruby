require "bundler/inline"

gemfile(true) do
  source 'https://rubygems.org'
  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  ruby '> 2.6'
  gem 'sentry-rails', path: "../../"
  gem 'railties', '~> 6.0.0'
  gem "pry"
end

require "pry"
require "action_view/railtie"
require "action_controller/railtie"
require 'sentry-rails'

Sentry.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
  config.logger = Logger.new($stdout)
end

ActiveSupport::Deprecation.silenced = true

class TestApp < Rails::Application
end

class TestController < ActionController::Base
  include Rails.application.routes.url_helpers

  def exception
    raise "foo"
  end
end

def app
  return @app if @app

  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.root = __dir__
  app.config.hosts = nil
  app.config.consider_all_requests_local = false

  app.config.logger = Logger.new($stdout)
  app.config.log_level = :debug
  Rails.logger = app.config.logger

  app.routes.append do
    get "/exception" => "test#exception"
  end

  app.initialize!
  Rails.application = app
  @app = app
  app
end

require "rack/test"
include Rack::Test::Methods

get "/exception"

sleep(2) # wait for the background_worker
