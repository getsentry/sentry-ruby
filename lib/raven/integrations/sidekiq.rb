require 'time'
require 'sidekiq'

module Raven
  class SidekiqCleanupMiddleware
    def call(_worker, _job, _queue)
      yield
    ensure
      Context.clear!
      BreadcrumbBuffer.clear!
    end
  end

  class SidekiqErrorHandler
    ACTIVEJOB_RESERVED_PREFIX = "_aj_".freeze

    def call(ex, context)
      context = filter_context(context)
      Raven.capture_exception(
        ex,
        :message => ex.message,
        :extra => { :sidekiq => context },
        :culprit => culprit_from_context(context)
      )
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

    # this will change in the future:
    # https://github.com/mperham/sidekiq/pull/3161
    def culprit_from_context(context)
      classname = (context["class"] || (context["job"] && context["job"]["class"]))
      if classname
        "Sidekiq/#{classname}"
      elsif context["event"]
        "Sidekiq/#{context['event']}"
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
