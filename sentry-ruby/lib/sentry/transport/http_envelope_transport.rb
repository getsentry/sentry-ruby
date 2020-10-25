require 'faraday'

module Sentry
  class HTTPEnvelopeTransport < HTTPTransport
    attr_accessor :conn, :adapter

    def initialize(*args)
      super
      @endpoint = @dsn.envelope_endpoint
    end

    def encode(event_hash)
      event_id = event_hash[:event_id] || event_hash['event_id']

      envelope = <<~ENVELOPE
        {"event_id":"#{event_id}","dsn":"#{configuration.dsn.to_s}","sdk":#{Sentry.sdk_meta.to_json},"sent_at":"#{DateTime.now.rfc3339}"}
        {"type":"event","content_type":"application/json"}
        #{event_hash.to_json}
      ENVELOPE

      [CONTENT_TYPE, envelope]
    end
  end
end
