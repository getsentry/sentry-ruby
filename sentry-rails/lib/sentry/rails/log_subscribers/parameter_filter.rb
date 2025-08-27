# frozen_string_literal: true

module Sentry
  module Rails
    module LogSubscribers
      # Shared utility module for filtering sensitive parameters in log subscribers.
      #
      # This module provides consistent parameter filtering across all Sentry Rails
      # log subscribers, leveraging Rails' built-in parameter filtering when available.
      # It automatically detects the correct Rails parameter filtering API based on
      # the Rails version and includes the appropriate implementation module.
      #
      # @example Usage in a log subscriber
      #   class MySubscriber < Sentry::Rails::LogSubscriber
      #     include Sentry::Rails::LogSubscribers::ParameterFilter
      #
      #     def my_event(event)
      #       if Sentry.configuration.send_default_pii && event.payload[:params]
      #         filtered_params = filter_sensitive_params(event.payload[:params])
      #         attributes[:params] = filtered_params unless filtered_params.empty?
      #       end
      #     end
      #   end
      module ParameterFilter
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
        # @return [Hash] Filtered parameters with sensitive data removed
        def filter_sensitive_params(params)
          return EMPTY_HASH unless params.is_a?(Hash)

          filter_parameters = ::Rails.application.config.filter_parameters
          parameter_filter = ParameterFilter.backend.new(filter_parameters)

          parameter_filter.filter(params)
        end
      end
    end
  end
end
