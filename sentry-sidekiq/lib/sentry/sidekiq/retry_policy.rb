# frozen_string_literal: true

module Sentry
  module Sidekiq
    class RetryPolicy
      DEFAULT_MAX_RETRIES = 25

      def self.build
        if ::Gem::Version.new(::Sidekiq::VERSION) >= ::Gem::Version.new("7.0")
          Sidekiq7.new
        elsif ::Sidekiq.respond_to?(:[])
          Sidekiq6.new
        else
          Legacy.new
        end
      end

      attr_reader :default_config

      def initialize(default_config)
        @default_config = default_config
      end

      def retryable?(job)
        retry_option = retry_option(job)
        # when `retry` is not specified, it's default is `true` and it means 25 retries.
        retry_option.nil? || retry_option == true || (retry_option.is_a?(Integer) && retry_option.positive?)
      end

      # @return [Integer] the number of retries allowed for the job
      # Tries to fetch the retry limit from the job config first,
      # then falls back to Sidekiq's configuration.
      def limit(job, sidekiq_config = nil)
        retry_option = retry_option(job)

        case retry_option
        when Integer
          retry_option
        when TrueClass, NilClass
          max_retries(sidekiq_config) || DEFAULT_MAX_RETRIES
        else
          0
        end
      end

      def retry_count(job)
        job && job["retry_count"]
      end

      def will_retry?(job)
        count = retry_count(job)
        next_count = count.nil? ? 0 : count + 1
        retryable?(job) && next_count < limit(job)
      end

      private

      def retry_option(job)
        job && job["retry"]
      end

      def max_retries(_sidekiq_config)
        default_config[:max_retries]
      end

      class Sidekiq7 < RetryPolicy
        def initialize(default_config = ::Sidekiq.default_configuration)
          super
        end

        private

        # Sidekiq 7.1.5+ passes the config to the error handler, so we should use that.
        # Sidekiq 7.0 -> 7.1.5 provides ::Sidekiq.default_configuration.
        def max_retries(sidekiq_config)
          config = sidekiq_config.is_a?(::Sidekiq::Config) ? sidekiq_config : default_config
          config[:max_retries]
        end
      end

      class Sidekiq6 < RetryPolicy
        def initialize(default_config = ::Sidekiq)
          super
        end
      end

      class Legacy < RetryPolicy
        def initialize(default_config = ::Sidekiq)
          super
        end

        private

        def max_retries(_sidekiq_config)
          default_config.options[:max_retries]
        end
      end
    end
  end
end
