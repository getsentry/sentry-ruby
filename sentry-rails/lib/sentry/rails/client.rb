module Sentry
  class Client
    def dispatch_background_event(event, hint)
      Sentry.background_worker.perform do
        # make sure the background worker returns AR connection if it accidentally acquire one during serialization
        ActiveRecord::Base.connection_pool.with_connection do
          send_event(event, hint)
        end
      end
    end
  end
end
