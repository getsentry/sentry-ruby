# frozen_string_literal: true

module Sentry
  class ThreadedPeriodicWorker
    include LoggingHelper

    attr_reader :thread

    def initialize(sdk_logger, interval)
      @thread = nil
      @exited = false
      @interval = interval
      @sdk_logger = sdk_logger

      @thread_mutex = Mutex.new
      @wake_condition = ConditionVariable.new
      @idle_condition = ConditionVariable.new

      @force_run = false
      @running = false
    end

    def ensure_thread
      @thread_mutex.synchronize do
        return false if @exited
        return true if @thread&.alive?

        @thread = Thread.new do
          loop do
            @thread_mutex.synchronize do
              @wake_condition.wait(@thread_mutex, @interval) unless @force_run
              @force_run = false
              @running = true
            end

            begin
              run
            ensure
              @thread_mutex.synchronize do
                @running = false
                @idle_condition.broadcast
              end
            end
          end
        end

        true
      end
    rescue ThreadError
      @thread_mutex.synchronize { @exited = true }
      log_debug("[#{self.class.name}] thread creation failed")
      false
    end

    def wake
      @thread_mutex.synchronize do
        @force_run = true
        @wake_condition.signal
      end

      true
    end

    def wait_until_idle
      @thread_mutex.synchronize do
        @idle_condition.wait(@thread_mutex) while @running || @force_run
      end
    end

    def kill
      thread = @thread_mutex.synchronize do
        @exited = true
        @force_run = false
        @idle_condition.broadcast
        @thread
      end

      # Only a started worker has a thread to kill (and to log about).
      # Guarding here keeps a never-started worker's teardown silent, so
      # killing one during test reset can't emit a stray debug line.
      return unless thread

      log_debug("[#{self.class.name}] thread killed")
      thread.kill
    end
  end
end
