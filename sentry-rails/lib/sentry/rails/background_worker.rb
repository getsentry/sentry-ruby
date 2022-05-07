module Sentry
  class BackgroundWorker
    def _perform(&block)
      block.call
    ensure
      # make sure the background worker returns AR connection if it accidentally acquire one during serialization
      ActiveRecord::Base.connection_pool.release_connection
    end
  end
end
