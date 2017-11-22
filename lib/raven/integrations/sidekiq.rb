require 'time'
require 'sidekiq'

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
    HAS_GLOBALID = const_defined?('GlobalID')

    def call(ex, context)
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
        format_globalid(context)
      end
    end

    def filter_context_hash(key, value)
      (key = key[3..-1]) if key [0..3] == ACTIVEJOB_RESERVED_PREFIX
      [key, filter_context(value)]
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

    def format_globalid(context)
      if HAS_GLOBALID && context.is_a?(GlobalID)
        context.to_s
      else
        context
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
