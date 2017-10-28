require 'time'
require 'sidekiq'
begin
  # Sidekiq 5 introduces JobRetry and stores the default max retry attempts there.
  require 'sidekiq/job_retry'
rescue LoadError # rubocop:disable Lint/HandleExceptions
end

module Raven
  class SidekiqCleanupMiddleware
    def call(_worker, job, queue)
      Raven.context.transaction.push "Sidekiq/#{job['class']}"
      Raven.extra_context(:sidekiq => job.merge("queue" => queue))
      yield
      Context.clear!
      BreadcrumbBuffer.clear!
    end
  end

  class SidekiqErrorHandler
    ACTIVEJOB_RESERVED_PREFIX = "_aj_".freeze

    def call(ex, context, options = {})
      configuration = options[:configuration] || Raven.configuration
      return if configuration.retryable_exception?(ex) && remaining_retries?(context)

      context = filter_context(context)
      Raven.context.transaction.push transaction_from_context(context)
      Raven.capture_exception(
        ex,
        :message => ex.message,
        :extra => { :sidekiq => context }
      )
      Context.clear!
      BreadcrumbBuffer.clear!
    end

    private

    # Once an ActiveJob is queued, ActiveRecord references get serialized into
    # some internal reserved keys, such as _aj_globalid.
    #
    # The problem is, if this job in turn gets queued back into ActiveJob with
    # these magic reserved keys, ActiveJob will throw up and error. We want to
    # capture these and mutate the keys so we can sanely report it.
    def filter_context(context)
      case context
      when Array
        context.map { |arg| filter_context(arg) }
      when Hash
        Hash[context.map { |key, value| filter_context_hash(key, value) }]
      else
        context
      end
    end

    def filter_context_hash(key, value)
      (key = key[3..-1]) if key [0..3] == ACTIVEJOB_RESERVED_PREFIX
      [key, filter_context(value)]
    end

    def remaining_retries?(context)
      job = context[:job] || context # Sidekiq < 4 does not have job key.
      return false unless job && job["retry"]
      job["retry_count"] < retry_attempts_from(job["retry"])
    end

    def retry_attempts_from(retries)
      if retries.is_a?(Integer)
        retries
      else
        default_max_attempts =
          if defined?(Sidekiq::JobRetry)
            Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS # Sidekiq 5
          else
            Sidekiq::Middleware::Server::RetryJobs::DEFAULT_MAX_RETRY_ATTEMPTS # Sidekiq < 5
          end

        Sidekiq.options.fetch(:max_retries, default_max_attempts)
      end
    end

    # this will change in the future:
    # https://github.com/mperham/sidekiq/pull/3161
    def transaction_from_context(context)
      classname = (context["wrapped"] || context["class"] ||
                    (context[:job] && (context[:job]["wrapped"] || context[:job]["class"]))
                  )
      if classname
        "Sidekiq/#{classname}"
      elsif context[:event]
        "Sidekiq/#{context[:event]}"
      else
        "Sidekiq"
      end
    end
  end
end

if Sidekiq::VERSION > '3'
  Sidekiq.configure_server do |config|
    config.error_handlers << Raven::SidekiqErrorHandler.new
    config.server_middleware do |chain|
      chain.add Raven::SidekiqCleanupMiddleware
    end
  end
end
