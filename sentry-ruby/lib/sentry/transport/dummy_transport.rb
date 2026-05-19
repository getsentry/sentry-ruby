# frozen_string_literal: true

module Sentry
  class DummyTransport < Transport
    attr_accessor :events, :envelopes

    def initialize(*)
      super
      @events = []
      @envelopes = []
    end

    def send_event(event)
      @events << event
      super
    end

    def send_envelope(envelope)
      @envelopes << envelope
    end

    # Empties the captured events and envelopes so `TestHelper.clear_sentry_events`
    # also clears the dummy transport instance
    def clear
      @events.clear
      @envelopes.clear
    end
  end
end
