require 'time'
require 'sidekiq'

module Raven
  class Sidekiq
    def call(_worker, msg, _queue)
      started_at = Time.now
      yield
    rescue Exception => ex
      Raven.capture_exception(ex, :extra => { :sidekiq => msg },
                                  :time_spent => Time.now-started_at)
      raise
    end
  end
end

if Sidekiq::VERSION < '3'
  # old behavior
  ::Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add ::Raven::Sidekiq
    end
  end
else
  Sidekiq.configure_server do |config|
    config.error_handlers << Proc.new do |ex, context|
      Raven.capture_exception(ex, :extra => {
        :sidekiq => filter_context(context)
      })
    end
  end
end

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
  # Strip any `_aj` prefixes from keys.
  # These keys come from an internal serialized object from ActiveJob.
  # Internally, there are a subset of keys that ActiveJob references, but
  # these are declared as private, and I don't think it's wise
  # to keep chasing what this list is. But they all use a common prefix, so
  # we want to strip this becuase ActiveJob will complain.
  # e.g.: _aj_globalid -> _globalid
  (key = key[3..-1]) if key [0..3] == "_aj_"
  [key, filter_context(value)]
end
