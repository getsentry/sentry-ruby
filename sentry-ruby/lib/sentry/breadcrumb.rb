module Sentry
  class Breadcrumb
    attr_accessor :category, :data, :message, :level, :timestamp, :type

    def initialize(category: nil, data: nil, message: nil, timestamp: nil, level: nil, type: nil)
      @category = category
      @data = data || {}
      @level = level
      @message = message
      @timestamp = timestamp || Sentry.utc_now.to_i
      @type = type
    end

    def to_hash
      {
        :category => @category,
        :data => @data,
        :level => @level,
        :message => @message,
        :timestamp => @timestamp,
        :type => @type
      }
    end
  end
end
