require 'rails'
require "active_record"
require "action_view/railtie"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_cable/engine"
# require "sprockets/railtie"
# require "rails/test_unit/railtie"
require 'sentry/rails'

ActiveSupport::Deprecation.silenced = true

# need to init app before establish connection so sqlite can place the database file under the correct project root
class TestApp < Rails::Application
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: "db")
ActiveRecord::Base.logger = Logger.new(nil)

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
  end

  create_table :comments, force: true do |t|
    t.integer :post_id
  end
end

class Post < ActiveRecord::Base
  has_many :comments
end

class Comment < ActiveRecord::Base
  belongs_to :post
end

class PostsController < ActionController::Base
  def index
    Post.all.to_a
    raise "foo"
  end

  def show
    p = Post.find(params[:id])

    render plain: p.id
  end
end

class HelloController < ActionController::Base
  prepend_view_path "spec/support/test_rails_app"

  def exception
    raise "An unhandled exception!"
  end

  def reporting
    render plain: Sentry.last_event_id
  end

  def view_exception
    render inline: "<%= foo %>"
  end

  def view
    render template: "test_template"
  end

  def world
    render :plain => "Hello World!"
  end

  def with_custom_instrumentation
    custom_event = "custom.instrument"
    ActiveSupport::Notifications.subscribe(custom_event) do |*args|
      data = args[-1]
      data += 1
    end

    ActiveSupport::Notifications.instrument(custom_event, 1)

    head :ok
  end

  def not_found
    raise ActionController::BadRequest
  end
end

def make_basic_app
  # Rails removes the support of multiple instances, which includes freezing some setting values.
  # This is the workaround to avoid FrozenError. Related issue: https://github.com/rails/rails/issues/42319
  ActiveSupport::Dependencies.autoload_once_paths = []
  ActiveSupport::Dependencies.autoload_paths = []

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
    get "/view", :to => "hello#view"
    get "/not_found", :to => "hello#not_found"
    get "/world", to: "hello#world"
    get "/with_custom_instrumentation", to: "hello#with_custom_instrumentation"
    resources :posts, only: [:index, :show]
    get "500", to: "hello#reporting"
    root :to => "hello#world"
  end

  app.initializer :configure_release do
    ENV["SENTRY_DSN"] = nil

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
  app
end
