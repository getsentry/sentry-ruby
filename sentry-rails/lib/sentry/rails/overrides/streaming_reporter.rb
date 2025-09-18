# frozen_string_literal: true

module Sentry
  module Rails
    module Overrides
      module StreamingReporter
        def log_error(exception)
          Sentry::Rails.capture_exception(exception)
          super
        end
      end
    end
  end
end
