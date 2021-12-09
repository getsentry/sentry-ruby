# frozen_string_literal: true

module Sentry
  module ArgumentCheckingHelper
    private

    def check_argument_type!(argument, expected_type)
      unless argument.is_a?(expected_type)
        raise ArgumentError, "expect the argument to be a #{expected_type}, got #{argument.class} (#{argument.inspect})"
      end
    end
  end
end
