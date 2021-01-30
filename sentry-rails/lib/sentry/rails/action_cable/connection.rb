# frozen_string_literal: true

require_relative 'exception_reporter'

module Sentry
  module Rails
    module ActionCable
      module Connection
        private

        def handle_open
          ExceptionReporter.capture(env, transaction_name: self.class.name) { super }
        end
      end
    end
  end
end
