module Sentry
  class DummyTransport < Transport
    attr_accessor :events

    def initialize(*)
      super
      @events = []
    end

    def send_event(data, options = {})
      @events << [generate_auth_header, data, options]
    end
  end
end
