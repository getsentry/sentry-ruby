# frozen_string_literal: true

require "active_record"

require "active_job/railtie"
require "action_view/railtie"
require "action_controller/railtie"

require "action_cable/engine"
require "active_storage/engine"

module Sentry
  module Rails
    module Test
      class Application < ::Rails::Application
        def self.define
          klass = Class.new(Sentry::TestRailsApp)

          klass.define_singleton_method(:name) {
            "Sentry::TestRailsApp_#{klass.version}::Anonymous#{object_id}"
          }

          klass.configure

          yield(klass) if block_given?

          klass.before_initialize!
          klass.initialize!
          klass.after_initialize!

          ::Rails.application = klass

          klass
        end

        def self.version
          @version ||= ::Rails.version.to_f.to_s
        end

        def self.root_path
          @root_path ||= Pathname(__dir__).join("..").expand_path
        end

        def self.schema_file
          @schema_file ||= root_path.join("db/schema.rb")
        end

        def self.database_url
          @__database_url__ ||=
            begin
              url = ENV["DATABASE_URL"]

              if url
                url
              else
                url =
                  case ENV["DATABASE"].to_s
                  when "sqlite3" then "sqlite3://#{db_path}"
                  when "postgresql" then "postgresql://postgres:postgres@#{db_host}:5432/sentry"
                  else
                    raise "Unsupported database for tests: #{ENV["DATABASE"].inspect}"
                  end

                # Set it too to make AR happy
                ENV["DATABASE_URL"] = url

                url
              end
            end
        end

        def self.db_path
          @db_path ||= root_path.join("db", "db.sqlite3")
        end

        def self.db_host
          @db_host ||= (ENV["DATABASE_HOST"] || "postgres")
        end

        def self.db_uri
          @db_url ||= URI(database_url)
        end

        def self.db_system
          @db_system ||= db_uri.scheme
        end

        def self.db_name
          @db_name ||= File.basename(db_uri.path[1..-1])
        end

        def self.application_file
          @application_file ||= begin
            current = Dir[root_path.join("config/applications/rails-*.rb")]
              .map { |f| File.basename(f, ".rb").split("-").last }
              .find { |f| f == version }

            "rails-#{current || "latest"}"
          end
        end

        def self.load_test_schema
          @__schema_loaded__ ||= begin
            # Silence migrations output
            ActiveRecord::Migration.verbose = false

            # We need to connect manually here
            case db_uri.scheme
            when "postgresql"
              ActiveRecord::Base.establish_connection(
                adapter: db_uri.scheme,
                host: db_uri.host,
                username: db_uri.user,
                password: db_uri.password,
                database: db_name
              )
            when "sqlite3"
              ActiveRecord::Base.establish_connection(
                adapter: db_uri.scheme,
                database: db_path.to_s
              )
            else
              ActiveRecord::Base.establish_connection(
                adapter: db_uri.scheme, database: db_name
              )
            end

            # Load schema from db/schema.rb into the current connection
            require Test::Application.schema_file

            true
          end
        end

        # Configure method that sets up base configuration
        # This can be inherited and extended by subclasses
        def configure
          config.root = Test::Application.root_path
          config.active_support.deprecation = :silence
          config.hosts = nil
          config.secret_key_base = "test 123"
          config.sdk_logger = ActiveSupport::Logger.new(nil)
          config.eager_load = true
          config.active_job.queue_adapter = :test
          config.cache_store = :memory_store
          config.action_controller.perform_caching = true
          config.active_storage.service = :test

          config.filter_parameters = [
            :password,
            :secret,
            :custom_secret,
            :api_key,
            :credit_card,
            :authorization,
            :token
          ]

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

        def cleanup!
          ::Rails.application = nil
        end

        require_relative "applications/#{application_file}"

        ::Rails.module_eval do
          def self.root
            Sentry::TestRailsApp.root_path
          end
        end
      end
    end
  end
end
