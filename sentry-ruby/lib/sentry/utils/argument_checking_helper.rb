# frozen_string_literal: true

module Sentry
  module ArgumentCheckingHelper
    private

    def check_argument_type!(argument, *expected_types)
      unless expected_types.any? { |t| argument.is_a?(t) }
        raise ArgumentError, "expect the argument to be a #{expected_types.join(' or ')}, got #{argument.class} (#{argument.inspect})"
      end
    end

    def check_argument_includes!(argument, values)
      unless values.include?(argument)
        raise ArgumentError, "expect the argument to be one of #{values.map(&:inspect).join(' or ')}, got #{argument.inspect}"
      end
    end
  end
end
