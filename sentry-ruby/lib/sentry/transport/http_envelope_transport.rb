require 'faraday'

module Sentry
  class HTTPEnvelopeTransport < HTTPTransport
    attr_accessor :conn, :adapter

    def initialize(*args)
      super
      @endpoint = @dsn.envelope_endpoint
    end

    def prepare_encoded_event(event)
      [CONTENT_TYPE, event.to_envelope]
    end
  end
end
