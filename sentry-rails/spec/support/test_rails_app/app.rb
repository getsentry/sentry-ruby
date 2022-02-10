ENV["RAILS_ENV"] = "test"

require 'rails'

if Rails.version.to_f < 5.2
  require "support/test_rails_app/apps/5-0"
  return
end

require "active_record"
require "active_job/railtie"
require "active_storage/engine" if Rails.version.to_f >= 5.2
require "action_cable/engine" if Rails.version.to_f >= 6.0
require "action_view/railtie"
require "action_controller/railtie"

# require "action_mailer/railtie"
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
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.integer "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name"
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table :posts, force: true do |t|
  end

  create_table :comments, force: true do |t|
    t.integer :post_id
  end
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  if defined?(ActiveStorage)
    if Rails.version.to_f < 6.0
      extend ActiveStorage::Attached::Macros
    else
      include ActiveStorage::Attached::Model
      include ActiveStorage::Reflection::ActiveRecordExtensions
      ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)
    end
  end
end

class Post < ApplicationRecord
  has_many :comments
  has_one_attached :cover if defined?(ActiveStorage)
end

class Comment < ApplicationRecord
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

  def attach
    p = Post.find(params[:id])

    attach_params = {
      io: File.open(File.join(Rails.root, 'public', 'sentry-logo.png')),
      filename: 'sentry-logo.png',
    }

    unless Rails.version.to_f < 6.1
      attach_params[:service_name] = "test"
    end

    p.cover.attach(attach_params)

    render plain: p.id end
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
  # Zeitwerk checks if registered loaders load paths repeatedly and raises error if that happens.
  # And because every new Rails::Application instance registers its own loader, we need to clear previously registered ones from Zeitwerk.
  Zeitwerk::Registry.loaders.clear if defined?(Zeitwerk)

  # Rails removes the support of multiple instances, which includes freezing some setting values.
  # This is the workaround to avoid FrozenError. Related issue: https://github.com/rails/rails/issues/42319
  ActiveSupport::Dependencies.autoload_once_paths = []
  ActiveSupport::Dependencies.autoload_paths = []

  # there are a few Rails initializers/finializers that register hook to the executor
  # because the callbacks are stored inside the `ActiveSupport::Executor` class instead of an instance
  # the callbacks duplicate after each time we initialize the application and cause issues when they're executed
  ActiveSupport::Executor.reset_callbacks(:run)
  ActiveSupport::Executor.reset_callbacks(:complete)

  # Rails uses this module to set a global context for its ErrorReporter feature.
  # this needs to be cleared so previously set context won't pollute later reportings (see ErrorSubscriber).
  ActiveSupport::ExecutionContext.clear if defined?(ActiveSupport::ExecutionContext)

  if defined?(ActionCable)
    ActionCable::Channel::Base.reset_callbacks(:subscribe)
    ActionCable::Channel::Base.reset_callbacks(:unsubscribe)
  end

  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.hosts = nil
  app.config.secret_key_base = "test"
  app.config.logger = Logger.new(nil)
  app.config.eager_load = true

  if ::Rails.version.to_f >= 5.2
    app.config.active_storage.service = :test
  end

  if ::Rails.version.to_f == 6.0
    app.config.active_record.sqlite3 = ActiveSupport::OrderedOptions.new
    app.config.active_record.sqlite3.represent_boolean_as_integer = nil
  end

  app.routes.append do
    get "/exception", :to => "hello#exception"
    get "/view_exception", :to => "hello#view_exception"
    get "/view", :to => "hello#view"
    get "/not_found", :to => "hello#not_found"
    get "/world", to: "hello#world"
    get "/with_custom_instrumentation", to: "hello#with_custom_instrumentation"
    resources :posts, only: [:index, :show] do
      member do
        get :attach
      end
    end
    get "500", to: "hello#reporting"
    root :to => "hello#world"
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

  Post.all.to_a # to run the sqlte version query first

  if Sentry.initialized?
    Sentry.get_current_scope.clear_breadcrumbs # and then clear breadcrumbs in case the above query is recorded
  end

  Rails.application = app
  app
end
