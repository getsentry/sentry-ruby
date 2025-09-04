# frozen_string_literal: true

require "bundler/setup"

Bundler.require

ENV["RAILS_ENV"] = "development"
ENV["DATABASE_URL"] = "sqlite3:tmp/rails_mini_development.sqlite3"

require "action_controller/railtie"
require "active_record/railtie"
require "active_job/railtie"

class RailsMiniApp < Rails::Application
  config.hosts = nil
  config.secret_key_base = "test_secret_key_base_for_rails_mini_app"
  config.eager_load = false
  config.logger = Logger.new($stdout)
  config.log_level = :debug
  config.api_only = true
  config.force_ssl = false

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

  def sample_job
    job = SampleJob.perform_later("Hello from Rails mini app!")

    Sentry.logger.info("SampleJob enqueued", job_id: job.job_id)

    render json: {
      message: "SampleJob enqueued successfully",
      job_id: job.job_id,
      job_class: job.class.name
    }
  end

  def database_job
    title = params[:title] || "Test Post from Job"
    job = DatabaseJob.perform_later(title)

    Sentry.logger.info("DatabaseJob enqueued", job_id: job.job_id, post_title: title)

    render json: {
      message: "DatabaseJob enqueued successfully",
      job_id: job.job_id,
      job_class: job.class.name,
      post_title: title
    }
  end

  def failing_job
    should_fail = params[:should_fail] != "false"
    job = FailingJob.perform_later(should_fail)

    Sentry.logger.info("FailingJob enqueued", job_id: job.job_id, should_fail: should_fail)

    render json: {
      message: "FailingJob enqueued successfully",
      job_id: job.job_id,
      job_class: job.class.name,
      should_fail: should_fail
    }
  end

  private

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, sentry-trace, baggage'
  end
end

RailsMiniApp.initialize!

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
end

Post.create!(title: "Welcome Post", content: "Welcome to the Rails mini app!")
Post.create!(title: "Sample Post", content: "This is a sample post for testing.")
User.create!(name: "Test User", email: "test@example.com")

RailsMiniApp.routes.draw do
  get '/health', to: 'events#health'
  get '/error', to: 'error#error'
  get '/trace_headers', to: 'events#trace_headers'
  get '/logged_events', to: 'events#logged_events'
  post '/clear_logged_events', to: 'events#clear_logged_events'

  get '/posts', to: 'posts#index'
  post '/posts', to: 'posts#create'
  get '/posts/:id', to: 'posts#show'

  post '/jobs/sample', to: 'jobs#sample_job'
  post '/jobs/database', to: 'jobs#database_job'
  post '/jobs/failing', to: 'jobs#failing_job'

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
