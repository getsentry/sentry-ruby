require 'raven/error'

module Raven

  module Transports

    class Transport

      attr_accessor :configuration

      def initialize(configuration)
        @configuration = configuration
      end

      def send(auth_header, data, options = {})
        raise Error.new('Abstract method not implemented')
      end

    protected

      def verify_configuration
        raise Error.new('No server specified') unless self.configuration.server
        raise Error.new('No public key specified') unless self.configuration.public_key
        raise Error.new('No secret key specified') unless self.configuration.secret_key
        raise Error.new('No project ID specified') unless self.configuration.project_id
      end

    end

  end

end
