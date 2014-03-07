module Raven
  class Sidekiq
    def call(worker, msg, queue)
      yield
    rescue => ex
      Raven.capture_exception(ex, :extra => { :sidekiq => msg })
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
    config.error_handlers << Proc.new {|ex,context| Raven.capture_exception(ex, context) }
  end
end
