module Sentry
  class SessionFlusher
    include LoggingHelper

    FLUSH_INTERVAL = 60

    def initialize(configuration)
      @thread = nil
      @pending_aggregates = {}
      @release = configuration.release
      @environment = configuration.environment
      @logger = configuration.logger

      log_debug("[Sessions] Sessions won't be captured without a valid release") unless @release
    end

    def flush
      # TODO-neel envelope/send here
      # maybe capture_envelope
      @pending_aggregates = {}
    end

    def add_session(session)
      return unless @release

      ensure_thread

      return unless Session::VALID_AGGREGATE_STATUSES.include?(session.status)
      @pending_aggregates[session.started_bucket] ||= init_aggregates
      @pending_aggregates[session.started_bucket][session.status] += 1
    end

    def kill
      @thread&.kill
    end

    private

    def init_aggregates
      Session::VALID_AGGREGATE_STATUSES.map { |k| [k, 0] }.to_h
    end

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
