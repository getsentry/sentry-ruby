# frozen_string_literal: true

require "concurrent/executor/thread_pool_executor"
require "concurrent/executor/immediate_executor"
require "concurrent/configuration"

module Sentry
  class BackgroundWorker
    include LoggingHelper

    attr_reader :max_queue, :number_of_threads, :logger

    def initialize(configuration)
      @max_queue = 30
      @number_of_threads = configuration.background_worker_threads
      @logger = configuration.logger
      @debug = configuration.debug

      @executor =
        if configuration.async
          log_debug("config.async is set, BackgroundWorker is disabled")
          Concurrent::ImmediateExecutor.new
        elsif @number_of_threads == 0
          log_debug("config.background_worker_threads is set to 0, all events will be sent synchronously")
          Concurrent::ImmediateExecutor.new
        else
          log_debug("initialized a background worker with #{@number_of_threads} threads")

          Concurrent::ThreadPoolExecutor.new(
            min_threads: 0,
            max_threads: @number_of_threads,
            max_queue: @max_queue,
            fallback_policy: :discard
          )
        end
    end

    # if you want to monkey-patch this method, please override `_perform` instead
    def perform(&block)
      @executor.post do
        begin
          _perform(&block)
        rescue Exception => e
          log_error("exception happened in background worker", e, debug: @debug)
        end
      end
    end

    private

    def _perform(&block)
      block.call
    end
  end
end
