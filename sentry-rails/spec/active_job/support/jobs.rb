# frozen_string_literal: true

require "active_job/railtie"

module Sentry
  module Specs
    module ActiveJob
      class FailingJob < ::ActiveJob::Base
        self.logger = nil

        class Boom < RuntimeError
        end

        def perform
          raise Boom, "Boom!"
        end
      end
    end
  end
end
