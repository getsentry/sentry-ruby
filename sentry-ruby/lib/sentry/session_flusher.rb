# frozen_string_literal: true

module Sentry
  class SessionFlusher
    include LoggingHelper

    FLUSH_INTERVAL = 60

    def initialize(configuration, client)
      @thread = nil
      @exited = false
      @client = client
      @pending_aggregates = {}
      @release = configuration.release
      @environment = configuration.environment
      @logger = configuration.logger

      log_debug("[Sessions] Sessions won't be captured without a valid release") unless @release
    end

    def flush
      return if @pending_aggregates.empty?
      envelope = pending_envelope

      Sentry.background_worker.perform do
        @client.transport.send_envelope(envelope)
      end

      @pending_aggregates = {}
    end

    def add_session(session)
      return if @exited
      return unless @release

      begin
        ensure_thread
      rescue ThreadError
        log_debug("Session flusher thread creation failed")
        @exited = true
        return
      end

      return unless Session::AGGREGATE_STATUSES.include?(session.status)
      @pending_aggregates[session.aggregation_key] ||= init_aggregates(session.aggregation_key)
      @pending_aggregates[session.aggregation_key][session.status] += 1
    end

    def kill
      log_debug("Killing session flusher")

      @exited = true
      @thread&.kill
    end

    private

    def init_aggregates(aggregation_key)
      aggregates = { started: aggregation_key.iso8601 }
      Session::AGGREGATE_STATUSES.each { |k| aggregates[k] = 0 }
      aggregates
    end

    def pending_envelope
      envelope = Envelope.new

      header = { type: 'sessions' }
      payload = { attrs: attrs, aggregates: @pending_aggregates.values }

      envelope.add_item(header, payload)
      envelope
    end

    def attrs
      { release: @release, environment: @environment }
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
