# frozen_string_literal: true

module Sentry
  class DummyTransport < Transport
    attr_accessor :events, :envelopes

    def initialize(*)
      super
      @events = []
      @envelopes = []
      @mutex = Mutex.new
    end

    def send_event(event)
      @mutex.synchronize { @events << event }
      super
    end

    def send_envelope(envelope)
      @mutex.synchronize { @envelopes << envelope }
    end

    # Empties the captured events and envelopes so `TestHelper.clear_sentry_events`
    # also clears the dummy transport instance
    def clear
      @mutex.synchronize do
        @events.clear
        @envelopes.clear
      end
    end
  end
end
