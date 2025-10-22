# frozen_string_literal: true

module Sentry
  class Interface
    # @return [Hash]
    def to_h
      Hash[instance_variables.map { |name| [name[1..-1].to_sym, instance_variable_get(name)] }]
    end
  end
end

require "sentry/interfaces/exception"
require "sentry/interfaces/request"
require "sentry/interfaces/single_exception"
require "sentry/interfaces/stacktrace"
require "sentry/interfaces/threads"
require "sentry/interfaces/mechanism"
