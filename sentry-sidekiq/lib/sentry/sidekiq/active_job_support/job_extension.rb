# frozen_string_literal: true

require "sentry/sidekiq/job_extension"

module Sentry
  module Sidekiq
    # Support for ActiveJob jobs run through Sidekiq, which reports them in one of
    # two modes:
    #
    # - By default, sentry-rails skips the Sidekiq adapter and sentry-sidekiq
    #   reports ActiveJob jobs like other Sidekiq jobs, through
    #   {ActiveJobSupport::JobExtension}.
    # - When the app removes the Sidekiq adapter from
    #   `config.rails.skippable_job_adapters`, sentry-rails reports them through
    #   {Sentry::Sidekiq::ActiveJobExtension}, and {ActiveJobSupport::ServerMiddleware}
    #   keeps sentry-sidekiq from reporting them a second time.
    module ActiveJobSupport
      RESERVED_KEY_PREFIX = /^_aj_/

      # Returns whether the Sidekiq job wraps an ActiveJob job.
      #
      # @param job [Hash]
      # @return [Boolean]
      def self.handles?(job)
        job.is_a?(Hash) && job.key?("wrapped")
      end

      # The extension sentry-sidekiq uses for ActiveJob jobs it reports itself. It
      # names jobs after the ActiveJob class and keeps ActiveJob's serialization
      # details out of error events.
      class JobExtension < Sentry::Sidekiq::JobExtension
        # Names the transaction `Sidekiq/<ActiveJob class>`.
        #
        # @see Sentry::JobExtensions::Extension#transaction_name
        def transaction_name(job:, **)
          "#{SIDEKIQ_NAME}/#{job["wrapped"]}"
        end

        # Also replaces ActiveJob's serialized values with readable ones.
        #
        # @see Sentry::Sidekiq::JobExtension#error_context
        def error_context(context)
          strip_reserved_keys(super)
        end

        private

        def strip_reserved_keys(value)
          case value
          when Array
            value.map { |item| strip_reserved_keys(item) }
          when Hash
            value.to_h { |key, item| [reserved_key?(key) ? key.to_s.sub(RESERVED_KEY_PREFIX, "") : key, strip_reserved_keys(item)] }
          else
            defined?(::GlobalID) && value.is_a?(::GlobalID) ? value.to_s : value
          end
        end

        def reserved_key?(key)
          key.to_s.match?(RESERVED_KEY_PREFIX)
        end
      end
    end
  end
end
