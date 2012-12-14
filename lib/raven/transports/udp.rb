require 'socket'

require 'raven/transport'
require 'raven/error'

module Raven

  module Transport

    class UDP < Transport

      def send(auth_header, data, options = {})
        payload = auth_header + "\n\n" + data
        conn.send payload, 0
      end

    private

      def conn
        @conn ||= UDPSocket.new.tap do |sock|
          sock.connect(self.configuration.host, self.configuration.port)
        end
      end

      def verify_configuration
        super
        raise Error.new('No port specified') unless self.configuration.port
      end

    end

  end

end
