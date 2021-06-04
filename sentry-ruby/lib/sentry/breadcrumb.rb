module Sentry
  class Breadcrumb
    DATA_SERIALIZATION_ERROR_MESSAGE = "[data were removed due to serialization issues]"

    attr_accessor :category, :data, :level, :timestamp, :type
    attr_reader :message

    def initialize(category: nil, data: nil, message: nil, timestamp: nil, level: nil, type: nil)
      @category = category
      @data = data || {}
      @level = level
      @timestamp = timestamp || Sentry.utc_now.to_i
      @type = type
      self.message = message
    end

    def to_hash
      {
        category: @category,
        data: serialized_data,
        level: @level,
        message: @message,
        timestamp: @timestamp,
        type: @type
      }
    end

    def message=(msg)
      @message = (msg || "").byteslice(0..Event::MAX_MESSAGE_SIZE_IN_BYTES)
    end

    private

    def serialized_data
      begin
        ::JSON.parse(::JSON.generate(@data))
      rescue Exception => e
        Sentry.logger.debug(LOGGER_PROGNAME) do
          <<~MSG
can't serialize breadcrumb data because of error: #{e}
data: #{@data}
          MSG
        end

        DATA_SERIALIZATION_ERROR_MESSAGE
      end
    end
  end
end
