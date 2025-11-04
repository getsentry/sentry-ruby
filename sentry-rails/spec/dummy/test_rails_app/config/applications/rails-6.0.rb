# frozen_string_literal: true

module Sentry
  class TestRailsApp < Sentry::Rails::Test::Application
    def configure
      super
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
