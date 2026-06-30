# frozen_string_literal: true

require "bundler/setup"

Bundler.require

ENV["RAILS_ENV"] = "development"
ENV["DATABASE_URL"] = "sqlite3:tmp/rails_mini_development.sqlite3"

require "action_controller/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "time"

# Point the broker-backed adapters at Redis. Sidekiq reads REDIS_URL on
# its own; Resque does not, so wire it up explicitly. Defaults to a local
# Redis when REDIS_URL is unset (e.g. running outside Docker Compose).
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
Resque.redis = redis_url if defined?(Resque)

class RailsMiniApp < Rails::Application
  config.hosts = nil
  config.secret_key_base = "test_secret_key_base_for_rails_mini_app"
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :debug
  config.api_only = true
  config.force_ssl = false

  # Select the ActiveJob queue adapter from the environment. This must be
  # assigned in the application body (not inside an `initializer` block):
  # ActiveJob's own `active_job.set_configs` initializer reads
  # `config.active_job.queue_adapter` and applies it via an `on_load`
  # hook that fires during boot, before app-defined initializers run. An
  # assignment made from an initializer would therefore be a silent no-op
  # and every adapter would fall back to the default :async.
  SUPPORTED_ACTIVE_JOB_ADAPTERS = {
    "async" => :async,
    "inline" => :inline,
    "sidekiq" => :sidekiq,
    "resque" => :resque,
    "delayed_job" => :delayed_job
  }.freeze

  adapter_name = ENV.fetch("SENTRY_E2E_ACTIVE_JOB_ADAPTER", "async").to_s.downcase
  unless SUPPORTED_ACTIVE_JOB_ADAPTERS.key?(adapter_name)
    raise "Unsupported ActiveJob adapter: #{adapter_name}"
  end

  config.active_job.queue_adapter = SUPPORTED_ACTIVE_JOB_ADAPTERS[adapter_name]
  config.x.active_job_adapter_name = adapter_name

  def debug_log_path
    @log_path ||= begin
      path = Pathname(__dir__).join("../../../log")
      FileUtils.mkdir_p(path) unless path.exist?
      path.realpath
    end
  end

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
      config.sdk_debug_transport_log_file = debug_log_path.join("sentry_debug_events.log")
      config.background_worker_threads = 0

      config.enable_logs = true
      config.structured_logging.logger_class = Sentry::DebugStructuredLogger
      config.structured_logging.file_path = debug_log_path.join("sentry_e2e_tests.log")

      config.rails.structured_logging.enabled = true

      config.rails.structured_logging.subscribers = {
        active_record: Sentry::Rails::LogSubscribers::ActiveRecordSubscriber,
        action_controller: Sentry::Rails::LogSubscribers::ActionControllerSubscriber,
        active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber
      }
    end
  end
end

class Post < ActiveRecord::Base
end

class User < ActiveRecord::Base
end

class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked

  discard_on ActiveJob::DeserializationError
end

class SampleJob < ApplicationJob
  queue_as :default

  def perform(message = "Hello from ActiveJob!")
    Rails.logger.info("SampleJob executed with message: #{message}")

    Post.count
    User.count

    message
  end
end

class DatabaseJob < ApplicationJob
  queue_as :default

  def perform(post_title = "Test Post")
    Rails.logger.info("DatabaseJob creating post: #{post_title}")

    post = Post.create!(title: post_title, content: "Content for #{post_title}")
    found_post = Post.find(post.id)

    Rails.logger.info("DatabaseJob found post: #{found_post.title}")

    found_post
  end
end

class FailingJob < ApplicationJob
  queue_as :default

  def perform(should_fail = true)
    Rails.logger.info("FailingJob started")

    if should_fail
      raise StandardError, "Intentional job failure for testing"
    end

    "Job completed successfully"
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
    sentry_initialized = Sentry.initialized?
    sentry_dsn = ENV["SENTRY_DSN"]

    render json: {
      status: "ok",
      timestamp: Time.now.utc.iso8601,
      sentry_initialized: sentry_initialized,
      sentry_dsn_configured: !sentry_dsn.nil? && !sentry_dsn.empty?,
      sentry_dsn: sentry_dsn,
      sentry_environment: sentry_initialized ? Sentry.configuration.environment : nil,
      debug_info: {
        sentry_loaded: defined?(Sentry),
        configuration_present: Sentry.respond_to?(:configuration),
        dsn_configured: Sentry.respond_to?(:configuration) && Sentry.configuration&.dsn.present?,
        env_dsn_value: sentry_dsn
      }
    }
  end

  def trace_headers
    headers = Sentry.get_trace_propagation_headers || {}
    render json: { headers: headers }
  end

  private

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, sentry-trace, baggage'
  end
end

class PostsController < ActionController::Base
  before_action :set_cors_headers
  def index
    posts = Post.all.to_a

    Sentry.logger.info("Posts index accessed", posts_count: posts.length)

    render json: {
      posts: posts.map { |p| { id: p.id, title: p.title, content: p.content } }
    }
  end

  def create
    post = Post.create!(post_params)

    Sentry.logger.info("Post created", post_id: post.id, title: post.title)

    render json: { post: { id: post.id, title: post.title, content: post.content } }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    post = Post.find(params[:id])
    render json: { post: { id: post.id, title: post.title, content: post.content } }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Post not found" }, status: :not_found
  end

  private

  def post_params
    params.require(:post).permit(:title, :content)
  end

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, sentry-trace, baggage'
  end
end

class JobsController < ActionController::Base
  before_action :set_cors_headers

  JOB_CLASSES = {
    "sample" => SampleJob,
    "database" => DatabaseJob,
    "failing" => FailingJob
  }.freeze

  def enqueue
    job_type = params[:job_type] || params[:id] || params[:job] || "sample"
    job_class = JOB_CLASSES[job_type.to_s]
    raise ActionController::BadRequest.new("Unsupported job type: #{job_type}") unless job_class

    args = Array(params[:args] || [])
    args = JSON.parse(args) if args.is_a?(String) && args.strip.start_with?("[")

    job = schedule_job(job_class, args)

    Sentry.logger.info(
      "#{job_class.name} enqueued",
      job_id: job.job_id,
      job_class: job.class.name,
      args: args
    )

    response_body = {
      message: "#{job_class.name} enqueued successfully",
      job_id: job.job_id,
      job_class: job.class.name,
      args: args
    }

    if job_type.to_s == "database"
      response_body[:post_title] = args[0] || "Test Post from Job"
    elsif job_type.to_s == "failing"
      response_body[:should_fail] = args.empty? ? true : args.first
    end

    render json: response_body
  end

  def active_job_adapter
    render json: {
      adapter: Rails.configuration.x.active_job_adapter_name,
      queue_adapter: ActiveJob::Base.queue_adapter.class.name
    }
  end

  private

  def schedule_job(job_class, args)
    if params[:wait_seconds].present?
      job_class.set(wait: params[:wait_seconds].to_i.seconds).perform_later(*args)
    elsif params[:wait_until].present?
      job_class.set(wait_until: Time.parse(params[:wait_until])).perform_later(*args)
    else
      job_class.perform_later(*args)
    end
  end

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, sentry-trace, baggage'
  end
end

RailsMiniApp.initialize!

# The web process owns schema setup. The worker (worker.rb) boots the same
# app in parallel and sets SENTRY_E2E_SKIP_DB_SETUP=true to skip this block,
# avoiding a concurrent `force: true` drop/create race on the shared SQLite
# file; it waits for these tables to appear before processing jobs.
unless ENV["SENTRY_E2E_SKIP_DB_SETUP"] == "true"
  ActiveRecord::Schema.define do
    create_table :posts, force: true do |t|
      t.string :title, null: false
      t.text :content
      t.timestamps
    end

    create_table :users, force: true do |t|
      t.string :name, null: false
      t.string :email
      t.timestamps
    end

    # Backing store for the :delayed_job adapter. Created unconditionally so
    # the same schema works regardless of which adapter the worker uses.
    create_table :delayed_jobs, force: true do |t|
      t.integer :priority, default: 0, null: false
      t.integer :attempts, default: 0, null: false
      t.text :handler, null: false
      t.text :last_error
      t.datetime :run_at
      t.datetime :locked_at
      t.datetime :failed_at
      t.string :locked_by
      t.string :queue
      t.timestamps null: true
    end
    add_index :delayed_jobs, [:priority, :run_at], name: "delayed_jobs_priority"
  end

  Post.create!(title: "Welcome Post", content: "Welcome to the Rails mini app!")
  Post.create!(title: "Sample Post", content: "This is a sample post for testing.")
  User.create!(name: "Test User", email: "test@example.com")
end

RailsMiniApp.routes.draw do
  get '/health', to: 'events#health'
  get '/error', to: 'error#error'
  get '/trace_headers', to: 'events#trace_headers'
  get '/logged_events', to: 'events#logged_events'
  post '/clear_logged_events', to: 'events#clear_logged_events'

  get '/posts', to: 'posts#index'
  post '/posts', to: 'posts#create'
  get '/posts/:id', to: 'posts#show'

  post '/jobs/enqueue', to: 'jobs#enqueue'
  post '/jobs/:job_type', to: 'jobs#enqueue'
  get '/jobs/adapter', to: 'jobs#active_job_adapter'

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
