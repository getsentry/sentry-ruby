# This class allows messages to be sent to Sentry asynchronously.  Whenever
# a call to `capture_exception` or `capture_message` is made, the parameters are
# wrapped in an event object which is then given to the `push` method below.
#
# This `push` method adds the event to a queue and returns immediately.
# Meanwhile, a background thread continously polls from this queue and sends
# messages to Sentry as it see's them queue up.
module Raven
  class FriendlyThreadQueue
    MAX_QUEUE_SIZE = 100
    SHUTDOWN_WAIT_RETRIES = 100
    SHUTDOWN_SLEEP_SEC = 0.05

    def self.push(event)
      @exception_queue << event

      start_exception_thread! unless @exception_thread.alive?
      flush_exception_queue if @exception_queue.length > MAX_QUEUE_SIZE
    end

    def self.start_background_thread!
      @exception_queue ||= Queue.new
      @exception_thread_mutex ||= Mutex.new

      start_exception_thread!
    end

    def self.shutdown_background_thread!
      if @exception_thread.alive?
        # wait 5 seconds for the exception_queue to clear
        SHUTDOWN_WAIT_RETRIES.times do
          break if @exception_thread.stop? && @exception_queue.empty?
          sleep SHUTDOWN_SLEEP_SEC
        end
        @exception_thread.kill.join
      end
      flush_exception_queue
    end

    if defined?(::Rails) && ::Rails.env.test?
      def self.wait_for_queue_to_clear
        # sleep for a moment to wait for the exception to get queued
        sleep 0.01
        expire = Time.current + 5.seconds
        sleep 0.01 until @exception_queue.empty? || Time.current > expire
        # sleep for another moment to wait for the exception to be "processed"
        sleep 0.01
      end

      def self.clear_queue!
        @exception_queue.clear
      end
    end

    def self.start_exception_thread!
      @exception_thread_mutex.synchronize do
        return if @exception_thread && @exception_thread.alive?

        @exception_thread = Thread.new do
          Raven.logger.info('starting background thread')
          loop do
            begin
              if defined?(::METRICS)
                ::METRICS.multi_gauge('sentry_exception_notifier_queue_size', @exception_queue.size)
                exception = @exception_queue.pop
                ::METRICS.time('rpc.sentry.response_time') do
                  Raven.send_event(exception)
                end
              else
                Raven.send_event(@exception_queue.pop)
              end
            rescue StandardError => e
              Raven.logger.warn("rescued error=#{e.inspect} backtrace=#{e.backtrace.inspect}")
            rescue Exception => e # rubocop:disable Lint/RescueException
              Raven.logger.warn("re-raising error=#{e.inspect} backtrace=#{e.backtrace.inspect}")
              raise
            end
          end
        end
      end
    end

    def self.flush_exception_queue
      return if @exception_queue.empty?

      Raven.logger.warn('flushing queue to log')
      begin
        loop do
          Raven.logger.warn("flush deliver=#{@exception_queue.pop(true).inspect}")
        end
      rescue ThreadError
        Raven.logger.warn('finished flushing queue')
      end
    end
  end
end
