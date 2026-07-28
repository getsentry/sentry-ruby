# frozen_string_literal: true

module Sentry
  module Rails
    # Shared utility for filtering sensitive parameters, leveraging Rails' built-in parameter
    # filtering when available. It automatically detects the correct Rails parameter filtering
    # API based on the Rails version.
    #
    # This is public API: it is a supported extension point for custom log subscribers, and it
    # is also what the SDK uses to redact the context users attach via `Rails.error.set_context`
    # before it is sent as the "rails.error" context.
    #
    # Mix it in to get `filter_sensitive_params` as an instance method, or call it directly on
    # the module.
    #
    # @example Usage in a log subscriber
    #   class MySubscriber < Sentry::Rails::LogSubscriber
    #     include Sentry::Rails::ParameterFilter
    #
    #     def my_event(event)
    #       if Sentry.configuration.send_default_pii && event.payload[:params]
    #         filtered_params = filter_sensitive_params(event.payload[:params])
    #         attributes[:params] = filtered_params unless filtered_params.empty?
    #       end
    #     end
    #   end
    #
    # @example Usage as a module function
    #   Sentry::Rails::ParameterFilter.filter_sensitive_params(password: "hunter2")
    #   # => { password: "[FILTERED]" }
    module ParameterFilter
      extend self

      EMPTY_HASH = {}.freeze

      if ::Rails.version.to_f >= 6.0
        def self.backend
          ActiveSupport::ParameterFilter
        end
      else
        def self.backend
          ActionDispatch::Http::ParameterFilter
        end
      end

      # Filter sensitive parameters from a hash, respecting Rails configuration.
      #
      # @param params [Hash] The parameters to filter
      # @return [Hash] Filtered parameters with sensitive data removed, or an empty hash if
      #   +params+ is not a Hash
      def filter_sensitive_params(params)
        return EMPTY_HASH unless params.is_a?(Hash)

        filter_parameters = ::Rails.application&.config&.filter_parameters

        # Without a booted application there are no filters configured, so there is
        # nothing to redact. This runs on the exception-capture path, where raising
        # would replace the user's exception with a NoMethodError from the SDK.
        return params if filter_parameters.nil?

        parameter_filter = ParameterFilter.backend.new(filter_parameters)

        parameter_filter.filter(params)
      end
    end
  end
end

require "sentry/rails/log_subscribers/parameter_filter"
