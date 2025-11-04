# frozen_string_literal: true

module Sentry
  class TestRailsApp < Sentry::Rails::Test::Application
    def cleanup!
      ActionCable::Channel::Base.reset_callbacks(:subscribe)
      ActionCable::Channel::Base.reset_callbacks(:unsubscribe)

      super
    end
  end
end
