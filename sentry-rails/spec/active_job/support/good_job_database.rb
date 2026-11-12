# frozen_string_literal: true

require "erb"

module Sentry
  module Rails
    module Test
      module GoodJobDatabase
        SKIP_MESSAGE = "GoodJob specs need PostgreSQL: set POSTGRES_URL " \
                       "(e.g. postgres://postgres:postgres@localhost:5432/sentry_test, see `mise run services:postgres`)"

        INSTALL_MIGRATION = "lib/generators/good_job/templates/install/migrations/create_good_jobs.rb.erb"

        module_function

        def url
          ENV["POSTGRES_URL"].presence
        end

        def connect
          return if @connected_record_class.equal?(::GoodJob::BaseRecord)

          ::GoodJob::BaseRecord.establish_connection(url)
          @connected_record_class = ::GoodJob::BaseRecord
          load_schema
        end

        def load_schema
          @schema_loaded ||= begin
            connection = ::GoodJob::BaseRecord.connection

            ActiveRecord::Migration.suppress_messages do
              connection.tables.grep(/\Agood_job/).each do |table|
                connection.drop_table(table, force: :cascade)
              end

              install_migration.exec_migration(connection, :up)
            end

            ::GoodJob::BaseRecord.descendants.each(&:reset_column_information)
            true
          end
        end

        def install_migration
          template = File.read(File.join(Gem.loaded_specs.fetch("good_job").full_gem_path, INSTALL_MIGRATION))
          source = ERB.new(template).result_with_hash(migration_version: "[#{ActiveRecord::Migration.current_version}]")
          namespace = Module.new
          namespace.module_eval(source)
          namespace.const_get(namespace.constants.first).new
        end
      end
    end
  end
end

RSpec.shared_context "good_job database" do
  before(:all) do
    skip Sentry::Rails::Test::GoodJobDatabase::SKIP_MESSAGE unless Sentry::Rails::Test::GoodJobDatabase.url

    Sentry::Rails::Test::GoodJobDatabase.connect
  end
end
