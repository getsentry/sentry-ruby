# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "rails"

require "active_record"
require "active_job/railtie"
require "action_view/railtie"
require "action_controller/railtie"

require 'sentry/rails'
require 'tempfile'

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
  elapsed("pre_initialize_cleanup") do
    run_pre_initialize_cleanup
  end

  app = nil

  elapsed("app_setup") do
    app = Class.new(TestApp) do
      def self.name
        "RailsTestApp"
      end
    end
  end

  elapsed("app_config") do
    app.config.active_support.deprecation = :silence
    app.config.action_controller.view_paths = "spec/dummy/test_rails_app"
    app.config.hosts = nil
    app.config.secret_key_base = "test"
    app.config.logger = ActiveSupport::Logger.new(nil)
    app.config.eager_load = true
    app.config.active_job.queue_adapter = :test
  end

  # Eager load namespaces can be accumulated after repeated initializations and make initialization
  # slower after each run
  # This is especially obvious in Rails 7.2, because of https://github.com/rails/rails/pull/49987, but other constants's
  # accumulation can also cause slowdown
  # Because this is not necessary for the test, we can simply clear it here
  elapsed("eager_load_namespaces_clear") do
    app.config.eager_load_namespaces.clear
  end

  elapsed("configure_app") do
    configure_app(app)
  end

  elapsed("routes_append") do
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
  end

  elapsed("sentry_init") do
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
  end

  elapsed("initialize") do
    app.initialize!
  end

  elapsed("rails_application_set") do
    Rails.application = app
  end

  elapsed("require_app_code") do
    # load application code for the Rails version
    require "dummy/test_rails_app/apps/#{FILE_NAME}"
  end

  elapsed("post_all") do
    Post.all.to_a # to run the sqlte version query first
  end

  elapsed("clear_breadcrumbs") do
    # and then clear breadcrumbs in case the above query is recorded
    Sentry.get_current_scope.clear_breadcrumbs if Sentry.initialized?
  end

  puts "\nElapsed Time Summary:\n\n"
  RECORDED_ELAPSED.each do |label, total|
    puts "#{label}: %.8f seconds" % total
  end
  puts "\n" + "*" * 80
  puts "\nTotal Elapsed Time: %.8f seconds\n" % RECORDED_ELAPSED.values.sum
  puts "\n" + "*" * 80

  app
end

def elapsed(label)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  yield
  stop = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  elapsed = (stop - start) / 1_000_000_000.0
  RECORDED_ELAPSED[label] += elapsed
  elapsed
end

RECORDED_ELAPSED = Hash.new { |h, k| h[k] = 0 }
