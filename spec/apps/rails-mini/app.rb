# frozen_string_literal: true

require "bundler/setup"

Bundler.require

ENV["RAILS_ENV"] = "development"

require "action_controller"

class RailsMiniApp < Rails::Application
  config.hosts = nil
  config.secret_key_base = "test_secret_key_base_for_rails_mini_app"
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :debug
  config.api_only = true
  config.force_ssl = false

  initializer :configure_sentry do
    Sentry.init do |config|
      config.dsn = ENV["SENTRY_DSN"]
      config.breadcrumbs_logger = [:active_support_logger, :http_logger, :redis_logger]
      config.traces_sample_rate = 1.0
      config.send_default_pii = true
      config.sdk_logger.level = ::Logger::DEBUG
      config.sdk_logger = Sentry::Logger.new($stdout)
      config.debug = true
      config.include_local_variables = true
      config.release = "sentry-ruby-rails-mini-#{Time.now.utc}"

      config.transport.transport_class = Sentry::DebugTransport
      config.sdk_debug_transport_log_file = "/workspace/sentry/log/sentry_debug_events.log"
      config.background_worker_threads = 0
    end
  end
end

class ErrorController < ActionController::Base
  before_action :set_cors_headers

  def error
    result = 1 / 0
    render json: { result: result }
  end

  private

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, sentry-trace, baggage'
  end
end

class EventsController < ActionController::Base
  before_action :set_cors_headers

  def health
    render json: {
      status: "ok",
      timestamp: Time.now.utc.iso8601,
      sentry_initialized: Sentry.initialized?,
      log_file_writable: check_log_file_writable
    }
  end

  def trace_headers
    headers = Sentry.get_trace_propagation_headers || {}
    render json: { headers: headers }
  end

  private

  def check_log_file_writable
    log_file_path = "/workspace/sentry/log/sentry_debug_events.log"
    File.writable?(File.dirname(log_file_path)) &&
      (!File.exist?(log_file_path) || File.writable?(log_file_path))
  rescue
    false
  end

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, sentry-trace, baggage'
  end
end

RailsMiniApp.initialize!

RailsMiniApp.routes.draw do
  get '/health', to: 'events#health'
  get '/error', to: 'error#error'
  get '/trace_headers', to: 'events#trace_headers'

  # Add CORS headers for cross-origin requests from JS app
  match '*path', to: proc { |env|
    [200, {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers' => 'Content-Type, Authorization, sentry-trace, baggage',
      'Content-Type' => 'application/json'
    }, ['{"status": "ok"}']]
  }, via: :options
end

if __FILE__ == $0
  require "rack"
  require "rack/handler/puma"

  port = ENV.fetch("SENTRY_E2E_RAILS_APP_PORT", "4000").to_i
  Rack::Handler::Puma.run(RailsMiniApp, Host: "0.0.0.0", Port: port)
end
