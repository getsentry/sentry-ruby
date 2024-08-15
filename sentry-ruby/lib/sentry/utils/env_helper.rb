# frozen_string_literal: true

module Sentry
  module EnvHelper
    TRUTHY_ENV_VALUES = %w(t true yes y 1 on).freeze
    FALSY_ENV_VALUES = %w(f false no n 0 off).freeze

    def env_to_bool(value, strict=false)
      value = value.to_s
      normalized = value.downcase

      if FALSY_ENV_VALUES.include?(normalized)
        return false
      end

      if TRUTHY_ENV_VALUES.include?(normalized)
        return true
      end

      return strict ? nil : !(value.nil? || value.empty?)
    end
  end
end
