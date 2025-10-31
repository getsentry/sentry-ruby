# frozen_string_literal: true

require "active_record"
require "active_job/railtie"
require "action_view/railtie"
require "action_controller/railtie"
require "active_storage/engine"

ActiveRecord::Base.logger = Logger.new(nil)

module Sentry
  module Rails
    module Test
      class Application < ::Rails::Application
        VERSION_MAP = Hash.new("latest").merge(
          "5.2" => "5-2",
          "6.0" => "6-0",
          "6.1" => "6-1",
          "7.0" => "7-0"
        ).freeze

        def self.define
          klass = Class.new(Sentry::TestRailsApp)

          klass.define_singleton_method(:name) {
            "Sentry::TestRailsApp::Anonymous#{object_id}"
          }

          klass.configure

          yield(klass) if block_given?

          klass.before_initialize!
          klass.initialize!
          klass.after_initialize!

          klass
        end

        def self.[](version)
          klasses[version.to_s] ||= Class.new(self) do
            def self.name
              "Sentry::TestRailsApp#{version.split(".").join("_")}"
            end
          end
        end

        def self.version
          @version ||= ::Rails.version.to_f.to_s
        end

        def self.klasses
          @klasses ||= {}
        end

        def self.root_path
          @root_path ||= Pathname(__dir__).join("..").expand_path
        end

        def self.schema_file
          @schema_file ||= root_path.join("db/schema.rb")
        end

        def self.application_file
          @application_file ||= VERSION_MAP[version]
        end

        # Configure method that sets up base configuration
        # This can be inherited and extended by subclasses
        def configure
          config.root = Test::Application.root_path
          config.logger = ActiveSupport::Logger.new(nil)
          config.active_support.deprecation = :silence
          config.hosts = nil
          config.secret_key_base = "test 123"
          config.sdk_logger = ActiveSupport::Logger.new(nil)
          config.eager_load = true
          config.active_job.queue_adapter = :test
          config.cache_store = :memory_store
          config.action_controller.perform_caching = true

          config.filter_parameters =
            [:password,
            :secret,
            :custom_secret,
            :api_key,
            :credit_card,
            :authorization,
            :token]

          # Eager load namespaces can be accumulated after repeated initializations and make initialization
          # slower after each run
          # This is especially obvious in Rails 7.2, because of https://github.com/rails/rails/pull/49987, but other constants's
          # accumulation can also cause slowdown
          # Because this is not necessary for the test, we can simply clear it here
          config.eager_load_namespaces.clear

          routes.append do
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

        def root_path
          self.class.root_path
        end

        def load_test_schema
          # Silence migrations output
          ActiveRecord::Migration.verbose = false

          # Load schema from db/schema.rb into the current connection
          require Test::Application.schema_file
        end

        def before_initialize!
          # no-op by default
        end

        def after_initialize!
          if Sentry.initialized?
            # Run a query to make sure the schema metadata gets loaded and cached
            Post.all.to_a.inspect

            # Clear breadcrumbs to avoid pollution from the query during test runs
            Sentry.get_current_scope.clear_breadcrumbs
          end
        end
      end
    end
  end
end

require_relative "applications/#{Sentry::Rails::Test::Application.application_file}"
