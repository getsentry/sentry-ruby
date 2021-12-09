# frozen_string_literal: true

module Sentry
  class DummyTransport < Transport
    attr_accessor :events

    def initialize(*)
      super
      @events = []
    end

    def send_event(event)
      @events << event
    end
  end
end
