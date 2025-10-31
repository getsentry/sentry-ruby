# frozen_string_literal: true

require "action_cable/engine"
require "active_storage/engine"

module Sentry
  class TestRailsApp < Sentry::Rails::Test::Application[5.2]
    def configure
      super
      config.active_storage.service = :test
    end

    def before_initialize!
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: root_path.join("db", "db.sqlite3")
      )
    end
  end
end
