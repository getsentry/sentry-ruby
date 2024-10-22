# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "rails"

require "active_record"
require "active_job/railtie"
require "action_view/railtie"
require "action_controller/railtie"

require 'sentry/rails'

ActiveRecord::Base.logger = Logger.new(nil)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: "db")

class TestApp < Rails::Application
end

v5_2 = Gem::Version.new("5.2")
v6_0 = Gem::Version.new("6.0")
v6_1 = Gem::Version.new("6.1")
v7_0 = Gem::Version.new("7.0")
v7_1 = Gem::Version.new("7.1.alpha")

FILE_NAME =
  case Gem::Version.new(Rails.version)
  when ->(v) { v < v5_2 }
    "5-0"
  when ->(v) { v.between?(v5_2, v6_0) }
    "5-2"
  when ->(v) { v.between?(v6_0, v6_1) }
    "6-0"
  when ->(v) { v.between?(v6_1, v7_0) }
    "6-1"
  when ->(v) { v > v7_0 && v < v7_1 }
    "7-0"
  when ->(v) { v >= v7_1 }
    "7-1"
  end

# require files and defined relevant setup methods for the Rails version
require "dummy/test_rails_app/configs/#{FILE_NAME}"

def make_basic_app(&block)
  run_pre_initialize_cleanup

  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.active_support.deprecation = :silence
  app.config.action_controller.view_paths = "spec/dummy/test_rails_app"
  app.config.hosts = nil
  app.config.secret_key_base = "test"
  app.config.logger = ActiveSupport::Logger.new(nil)
  app.config.eager_load = false
  app.config.active_job.queue_adapter = :test
  app.config.cache_store = :memory_store
  app.config.action_controller.perform_caching = true
  app.config.filter_parameters += [:password, :secret]

  # Eager load namespaces can be accumulated after repeated initializations and make initialization
  # slower after each run
  # This is especially obvious in Rails 7.2, because of https://github.com/rails/rails/pull/49987, but other constants's
  # accumulation can also cause slowdown
  # Because this is not necessary for the test, we can simply clear it here
  app.config.eager_load_namespaces.clear

  configure_app(app)

  app.routes.append do
    get "/exception", to: "hello#exception"
    get "/view_exception", to: "hello#view_exception"
    get "/view", to: "hello#view"
    get "/not_found", to: "hello#not_found"
    get "/world", to: "hello#world"
    get "/with_custom_instrumentation", to: "hello#with_custom_instrumentation"
    resources :posts, only: [:index, :show] do
      member do
        get :attach
      end
    end
    get "500", to: "hello#reporting"
    root to: "hello#world"
  end

  app.initializer :configure_sentry do
    Sentry.init do |config|
      config.release = 'beta'
      config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
      config.transport.transport_class = Sentry::DummyTransport
      # for sending events synchronously
      config.background_worker_threads = 0
      config.capture_exception_frame_locals = true
      yield(config, app) if block_given?
    end
  end

  app.initialize!

  Rails.application = app

  # load application code for the Rails version
  require "dummy/test_rails_app/apps/#{FILE_NAME}"

  Post.all.to_a # to run the sqlte version query first

  # and then clear breadcrumbs in case the above query is recorded
  Sentry.get_current_scope.clear_breadcrumbs if Sentry.initialized?

  app
end
