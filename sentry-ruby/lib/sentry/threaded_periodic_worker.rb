# frozen_string_literal: true

module Sentry
  class ThreadedPeriodicWorker
    include LoggingHelper

    def initialize(sdk_logger, interval)
      @thread = nil
      @exited = false
      @interval = interval
      @sdk_logger = sdk_logger
    end

    def ensure_thread
      return false if @exited
      return true if @thread&.alive?

      @thread = Thread.new do
        loop do
          sleep(@interval)
          run
        end
      end

      true
    rescue ThreadError
      log_debug("[#{self.class.name}] thread creation failed")
      @exited = true
      false
    end

    def kill
      @exited = true

      # Only a started worker has a thread to kill (and to log about).
      # Guarding here keeps a never-started worker's teardown silent, so
      # killing one during test reset can't emit a stray debug line.
      return unless @thread

      log_debug("[#{self.class.name}] thread killed")
      @thread.kill
    end
  end
end
