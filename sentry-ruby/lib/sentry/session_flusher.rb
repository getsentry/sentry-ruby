module Sentry
  class SessionFlusher
    FLUSH_INTERVAL = 60

    def initialize
      @thread = nil
      @pending_sessions = []
      @pending_aggregates = Hash.new(0)
    end

    def flush
      # TODO-neel envelope/send here
      # maybe capture_envelope
      @pending_sessions = []
      @pending_aggregates = Hash.new(0)
    end

    def add_aggregate_session(session)
      # TODO-neel deal with the numbers here once session structure is done
    end

    def add_session(session)
      ensure_thread

      if session.mode == :request
        add_aggregate_session(session)
      else
        @pending_sessions << session # TODO-neel json?
      end
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
