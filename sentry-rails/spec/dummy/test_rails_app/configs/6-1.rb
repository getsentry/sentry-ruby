# frozen_string_literal: true

require "active_storage/engine"
require "action_cable/engine"

def run_pre_initialize_cleanup
  ActionCable::Channel::Base.reset_callbacks(:subscribe)
  ActionCable::Channel::Base.reset_callbacks(:unsubscribe)
end

def configure_app(app)
  app.config.active_storage.service = :test
end
