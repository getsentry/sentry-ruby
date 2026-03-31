# frozen_string_literal: true

# Yabeda-Mini: A minimal Rails app for testing the sentry-yabeda adapter.
#
# Usage:
#   cd spec/apps/yabeda-mini
#   bundle install
#   bundle exec ruby app.rb
#
# Then hit:
#   GET  /health          — Check Sentry & Yabeda status
#   GET  /posts           — List posts (increments request counter, measures response time)
#   POST /posts           — Create a post (increments counter with payment_method tag)
#   GET  /error           — Trigger an error (increments error counter)
#   GET  /metrics         — Inspect buffered Sentry metric envelopes
#   POST /clear_metrics   — Clear the metric log file
#
# Metrics log is written to log/sentry_debug_events.log

require "bundler/setup"
Bundler.require

ENV["RAILS_ENV"] = "development"
ENV["DATABASE_URL"] = "sqlite3:tmp/yabeda_mini_development.sqlite3"

require "action_controller/railtie"
require "active_record/railtie"
require "active_job/railtie"

# ---------------------------------------------------------------------------
# Yabeda metric definitions
# ---------------------------------------------------------------------------
Yabeda.configure do
  group :app do
    counter   :requests_total,   comment: "Total HTTP requests",      tags: %i[controller action status]
    counter   :errors_total,     comment: "Total unhandled errors",    tags: %i[error_class]
    gauge     :queue_depth,      comment: "Simulated job queue depth", tags: %i[queue_name]
    histogram :request_duration, comment: "Request duration",          tags: %i[controller action],
              unit: :milliseconds,
              buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
  end

  group :business do
    counter :posts_created, comment: "Posts created", tags: %i[source]
  end
end

# ---------------------------------------------------------------------------
# Rails application
# ---------------------------------------------------------------------------
# Patch DebugTransport to also log envelopes sent via send_envelope.
# DebugTransport inherits from SimpleDelegator so send_envelope is forwarded
# via method_missing to the HTTP backend. We define it directly to intercept.
class Sentry::DebugTransport
  def send_envelope(envelope)
    log_envelope(envelope)
    __getobj__.send_envelope(envelope)
  rescue => e
    # Swallow HTTP errors when using a fake DSN — the envelope is already logged.
  end
end

class YabedaMiniApp < Rails::Application
  config.hosts = nil
  config.secret_key_base = "yabeda_mini_secret_key_base"
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :debug
  config.api_only = true
  config.force_ssl = false

  def debug_log_path
    @log_path ||= begin
      path = Pathname(__dir__).join("log")
      FileUtils.mkdir_p(path) unless path.exist?
      path.realpath
    end
  end

  initializer :configure_sentry do
    Sentry.init do |config|
      config.dsn = ENV.fetch("SENTRY_DSN", "http://examplePublicKey@o0.ingest.sentry.io/0")
      config.traces_sample_rate = 1.0
      config.send_default_pii = true
      config.debug = true
      config.sdk_logger = Sentry::Logger.new($stdout)
      config.sdk_logger.level = ::Logger::DEBUG
      config.transport.transport_class = Sentry::DebugTransport
      config.sdk_debug_transport_log_file = debug_log_path.join("sentry_debug_events.log")
      config.background_worker_threads = 0
      config.enable_metrics = true
      config.release = "yabeda-mini@0.1.0"
      config.environment = "development"
    end
  end
end

# Models
class Post < ActiveRecord::Base
end

# Controllers
class ApplicationController < ActionController::API
  around_action :track_metrics

  private

  def track_metrics
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
    Yabeda.app.request_duration.measure(
      { controller: controller_name, action: action_name },
      duration_ms
    )
    Yabeda.app.requests_total.increment(
      { controller: controller_name, action: action_name, status: response.status.to_s }
    )
  end
end

class HealthController < ApplicationController
  skip_around_action :track_metrics

  def show
    render json: {
      status: "ok",
      sentry_initialized: Sentry.initialized?,
      sentry_metrics_enabled: Sentry.initialized? && Sentry.configuration.enable_metrics,
      yabeda_configured: Yabeda.configured?,
      yabeda_adapters: Yabeda.adapters.keys,
      registered_metrics: Yabeda.metrics.keys
    }
  end
end

class PostsController < ApplicationController
  def index
    posts = Post.all.to_a
    # Simulate varying queue depth
    Yabeda.app.queue_depth.set({ queue_name: "default" }, rand(0..20))
    render json: { posts: posts.map { |p| { id: p.id, title: p.title } } }
  end

  def create
    post = Post.create!(title: params[:title] || "Untitled", content: params[:content])
    Yabeda.business.posts_created.increment({ source: params[:source] || "api" })
    render json: { post: { id: post.id, title: post.title } }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

class ErrorController < ApplicationController
  def trigger
    Yabeda.app.errors_total.increment({ error_class: "ZeroDivisionError" })
    1 / 0
  end
end

class MetricsController < ApplicationController
  skip_around_action :track_metrics

  def index
    log_file = YabedaMiniApp.new.debug_log_path.join("sentry_debug_events.log")

    envelopes = if File.exist?(log_file)
      File.readlines(log_file).filter_map do |line|
        data = JSON.parse(line)
        metric_items = data["items"]&.select { |i| i.dig("headers", "type") == "trace_metric" }
        next if metric_items.nil? || metric_items.empty?

        {
          timestamp: data["timestamp"],
          metrics: metric_items.flat_map { |i| i.dig("payload", "items") || [] }
        }
      end
    else
      []
    end

    total_metrics = envelopes.sum { |e| e[:metrics].size }

    render json: {
      total_envelopes: envelopes.size,
      total_metrics: total_metrics,
      envelopes: envelopes
    }
  end

  def flush
    buffer = Sentry.get_current_client.instance_variable_get(:@metric_event_buffer)
    count = buffer&.size || 0
    buffer&.flush
    render json: { status: "flushed", metrics_flushed: count }
  end

  def clear
    log_file = YabedaMiniApp.new.debug_log_path.join("sentry_debug_events.log")
    File.write(log_file, "") if File.exist?(log_file)
    render json: { status: "cleared" }
  end
end

# StartUp
YabedaMiniApp.initialize!

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.string :title, null: false
    t.text :content
    t.timestamps
  end
end

Post.create!(title: "Welcome", content: "First post in yabeda-mini")
Post.create!(title: "Metrics Test", content: "This post exists so /posts has data")

YabedaMiniApp.routes.draw do
  get  "/health",        to: "health#show"
  get  "/posts",         to: "posts#index"
  post "/posts",         to: "posts#create"
  get  "/error",         to: "error#trigger"
  get  "/metrics",       to: "metrics#index"
  post "/flush_metrics", to: "metrics#flush"
  post "/clear_metrics", to: "metrics#clear"
end

if __FILE__ == $0
  require "rack"
  require "rack/handler/puma"

  port = ENV.fetch("SENTRY_E2E_YABEDA_APP_PORT", "4002").to_i
  puts "\n#{"=" * 60}"
  puts "  Yabeda-Mini running on http://0.0.0.0:#{port}"
  puts "  Endpoints:"
  puts "    GET  /health        — Sentry & Yabeda status"
  puts "    GET  /posts         — List posts (emits metrics)"
  puts "    POST /posts         — Create post (emits business counter)"
  puts "    GET  /error         — Trigger error (emits error counter)"
  puts "    GET  /metrics        — Inspect captured Sentry metric envelopes"
  puts "    POST /flush_metrics  — Flush metric buffer to log"
  puts "    POST /clear_metrics  — Clear metric log"
  puts "#{"=" * 60}\n\n"

  Rack::Handler::Puma.run(YabedaMiniApp, Host: "0.0.0.0", Port: port)
end
