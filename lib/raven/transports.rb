require 'raven/error'

module Raven
  module Transports
    class Transport
      attr_accessor :configuration

      def initialize(configuration)
        @configuration = configuration
      end

      def send_event # (auth_header, data, options = {})
        raise NotImplementedError, 'Abstract method not implemented'
      end
    end
  end
end
