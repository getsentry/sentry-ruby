module Raven
  class Sidekiq
    def call(worker, msg, queue)
      begin
        yield
      rescue => ex
        Raven.capture_exception(ex, :extra => {:sidekiq => msg})
        raise
      end
    end
  end
end

::Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ::Raven::Sidekiq
  end
end