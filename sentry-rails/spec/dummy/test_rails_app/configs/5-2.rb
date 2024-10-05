# frozen_string_literal: true

require "active_storage/engine"

def run_pre_initialize_cleanup; end

def configure_app(app)
  app.config.active_storage.service = :test
end
