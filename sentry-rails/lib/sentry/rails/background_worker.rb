module Sentry
  class BackgroundWorker
    def _perform(&block)
      # make sure the background worker returns AR connection if it accidentally acquire one during serialization
      ::Rails.application.executor.wrap do
        block.call
      end
    end
  end
end
