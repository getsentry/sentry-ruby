# frozen_string_literal: true

require "bundler/inline"

ENV["RAILS_ENV"] = "development"

gemfile(true) do
  source 'https://rubygems.org'

  gem "puma"
  gem 'railties', '~> 8.0'
  gem 'actionpack', '~> 8.0'
  gem 'sentry-ruby', path: Pathname(__dir__).join("../../..").realpath
  gem 'sentry-rails', path: Pathname(__dir__).join("../../..").realpath
end

require "action_controller"

class RailsMiniApp < Rails::Application
  config.hosts = nil
  config.secret_key_base = "test_secret_key_base_for_rails_mini_app"
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :debug

  # Disable some Rails features we don't need
  config.api_only = true
  config.force_ssl = false

  # Validate DSN before starting
  initializer :validate_dsn, before: :configure_sentry do
    dsn_string = ENV["SENTRY_DSN"]

    if dsn_string.nil? || dsn_string.empty?
      puts "ERROR: SENTRY_DSN environment variable is required but not set"
      exit(1)
    end

    begin
      dsn = Sentry::DSN.new(dsn_string)
      unless dsn.valid?
        puts "ERROR: Invalid SENTRY_DSN: #{dsn_string}"
        puts "DSN must include host, path, public_key, and project_id"
        exit(1)
      end
      puts "✅ SENTRY_DSN validation passed: #{dsn_string}"
    rescue URI::InvalidURIError => e
      puts "ERROR: Invalid SENTRY_DSN format: #{e.message}"
      exit(1)
    rescue => e
      puts "ERROR: Failed to parse SENTRY_DSN: #{e.message}"
      exit(1)
    end
  end

  # Configure Sentry
  initializer :configure_sentry do
    Sentry.init do |config|
      config.dsn = ENV["SENTRY_DSN"]
      config.breadcrumbs_logger = [:active_support_logger, :http_logger, :redis_logger]
      config.traces_sample_rate = 1.0
      config.send_default_pii = true
      config.sdk_logger.level = ::Logger::DEBUG
      config.sdk_logger = Sentry::Logger.new($stdout)
      config.include_local_variables = true
      config.release = "sentry-ruby-rails-mini-#{Time.now.utc}"

      config.transport.transport_class = Sentry::DebugTransport
      config.sdk_debug_transport_log_file = File.join(Dir.pwd, "log", "sentry_debug_events.log")
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
    log_file_path = File.join(Dir.pwd, "log", "sentry_debug_events.log")
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

  Rack::Handler::Puma.run(RailsMiniApp, Host: "0.0.0.0", Port: 5000)
end
