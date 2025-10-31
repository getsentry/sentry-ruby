# frozen_string_literal: true

require "action_cable/engine"
require "active_storage/engine"

module Sentry
  class TestRailsApp < Sentry::Rails::Test::Application[6.0]
    def configure
      super
      config.active_storage.service = :test
      config.active_record.sqlite3 = ActiveSupport::OrderedOptions.new
      config.active_record.sqlite3.represent_boolean_as_integer = nil
    end

    def before_initialize!
      ActionCable::Channel::Base.reset_callbacks(:subscribe)
      ActionCable::Channel::Base.reset_callbacks(:unsubscribe)

      super
    end
  end
end
