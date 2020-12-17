require "concurrent/executor/thread_pool_executor"

module Sentry
  class BackgroundWorker
    attr_reader :max_queue, :number_of_threads

    def initialize(configuration)
      @max_queue = 30
      @number_of_threads = configuration.background_worker_threads

      @executor =
        if @number_of_threads == 0
          configuration.logger.debug(LOGGER_PROGNAME) { "config.background_worker_threads is set to 0, all events will be sent synchronously" }
          Concurrent::ImmediateExecutor.new
        else
          configuration.logger.debug(LOGGER_PROGNAME) { "initialized a background worker with #{@number_of_threads} threads" }

          Concurrent::ThreadPoolExecutor.new(
            min_threads: 0,
            max_threads: @number_of_threads,
            max_queue: @max_queue
          )
        end
    end

    def perform(&block)
      @executor.post do
        block.call
      end
    end
  end
end
