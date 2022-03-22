module Sentry
  class BackgroundWorker
    def _perform(&block)
      # some applications have partial or even no AR connection
      if ActiveRecord::Base.connected?
        # make sure the background worker returns AR connection if it accidentally acquire one during serialization
        ActiveRecord::Base.connection_pool.with_connection do
          block.call
        end
      else
        block.call
      end
    end
  end
end
