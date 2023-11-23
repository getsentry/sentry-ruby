module Sentry
  module Spotlight
    # Sentry Spotlight configuration.
    class Configuration

      # When enabled, Sentry will send all events and traces to the provided 
      # Spotlight Sidecar URL.
      # Defaults to false.
      # @return [Boolean]
      attr_reader :enabled
      
      # Spotlight Sidecar URL as a String.
      # Defaults to "http://localhost:8969/stream"
      # @return [String]
      attr_accessor :sidecar_url
      
      def initialize
        @enabled = false
        @sidecar_url = "http://localhost:8969/stream"
      end

      def enabled?
        enabled
      end

      # Enables or disables Spotlight.
      def enabled=(value)
        unless [true, false].include?(value)
         raise ArgumentError, "Spotlight config.enabled must be a boolean"
        end

        if value == true
          unless ['development', 'test'].include?(environment_from_env)
            # Using the default logger here for a one-off warning.
            ::Sentry::Logger.new(STDOUT).warn("[Spotlight] Spotlight is enabled in a non-development environment!")
          end
        end
      end

      private

      # TODO: Sentry::Configuration already reads the env the same way as below, but it also has a way to _set_ environment
      # in it's config. So this introduces a bug where env could be different, depending on whether the user set the environment
      # manually.
      def environment_from_env
        ENV['SENTRY_CURRENT_ENV'] || ENV['SENTRY_ENVIRONMENT'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
      end
    end
  end
end
