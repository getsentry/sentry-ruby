module Sentry
  class BenchmarkTransport < Transport
    attr_accessor :events

    def initialize(*)
      super
      @events = []
    end

    def send_event(event)
      @events << encode(event.to_hash)
    end
  end
end
