module Sentry
  module Transports
    class Dummy < Transport
      attr_accessor :events

      def initialize(*)
        super
        @events = []
      end

      def send_event(auth_header, data, options = {})
        @events << [auth_header, data, options]
      end
    end
  end
end
