# frozen_string_literal: true

require "action_cable/engine"
require "active_storage/engine"

module Sentry
  class TestRailsApp < Sentry::Rails::Test::Application[6.1]
    def configure
      super
      config.active_storage.service = :test
    end

    def before_initialize!
      ActionCable::Channel::Base.reset_callbacks(:subscribe)
      ActionCable::Channel::Base.reset_callbacks(:unsubscribe)

      super
    end
  end
end
