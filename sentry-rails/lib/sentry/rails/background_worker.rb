module Sentry
  class BackgroundWorker
    def perform(&block)
      @executor.post do
        # make sure the background worker returns AR connection if it accidentally acquire one during serialization
        ActiveRecord::Base.connection_pool.with_connection do
          block.call
        end
      end
    end
  end
end
