module Sentry
  class SessionFlusher
    include LoggingHelper

    FLUSH_INTERVAL = 60

    def initialize(configuration)
      @thread = nil
      @pending_aggregates = Hash.new(0)
      @release = configuration.release
      @environment = configuration.environment

      log_debug("[Sessions] Sessions won't be captured without a valid release") unless @release
    end

    def flush
      # TODO-neel envelope/send here
      # maybe capture_envelope
      @pending_aggregates = Hash.new(0)
    end

    def add_session(session)
      return unless @release

      ensure_thread
      # TODO-neel deal with the numbers here once session structure is done
    end

    def kill
      @thread&.kill
    end

    private

    def ensure_thread
      return if @thread&.alive?

      @thread = Thread.new do
        loop do
          sleep(FLUSH_INTERVAL)
          flush
        end
      end
    end

  end
end
