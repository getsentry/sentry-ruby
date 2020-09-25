module Sentry
  class Breadcrumb
    attr_accessor :category, :data, :message, :level, :timestamp, :type

    def initialize
      @category = nil
      @data = {}
      @level = nil
      @message = nil
      @timestamp = Time.now.to_i
      @type = nil
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
