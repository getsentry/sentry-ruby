# frozen_string_literal: true

require "sentry/test_helper"
require "dummy/test_rails_app/config/application"

module Sentry
  module Rails
    module TestHelper
      module_function

      include Sentry::TestHelper

      def make_basic_app(&block)
        Test::Application.define do |app|
          app.initializer :configure_sentry do
            Sentry.init do |config|
              config.release = 'beta'
              config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
              config.transport.transport_class = Sentry::DummyTransport

              # For sending events synchronously
              config.background_worker_threads = 0
              config.include_local_variables = true

              yield(config, app) if block_given?
            end
          end
        end
      end
    end
  end
end
