# frozen_string_literal: true

require "time"

module Sentry
  module Utils
    module Latency
      module_function

      def milliseconds_since(time)
        return unless time

        time = Time.parse(time) if time.is_a?(String)
        (Time.now.to_f - time.to_f) * 1000.0
      end
    end
  end
end
