module Sentry
  class Envelope
    def initialize(headers)
      @headers = headers
      @items = []
    end

    def add_item(headers, payload)
      @items << [headers, payload]
    end

    def to_s
      payload = @items.map do |item_headers, item_payload|
        <<~ENVELOPE
          #{JSON.generate(item_headers)}
          #{JSON.generate(item_payload)}
        ENVELOPE
      end.join("\n")

      "#{JSON.generate(@headers)}\n#{payload}"
    end
  end
end
