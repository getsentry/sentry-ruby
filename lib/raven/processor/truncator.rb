module Raven
  class Processor::Truncator < Processor
    attr_accessor :event_bytesize_limit

    def initialize(client)
      super
      self.event_bytesize_limit = client.configuration.event_bytesize_limit
    end

    def process(value)
      value.each_with_object(value) { |(k, v), memo| memo[k] = truncate(v) }
    end

    def truncate(v)
      if v.respond_to?(:bytesize) && v.bytesize >= event_bytesize_limit
        v.byteslice(0...event_bytesize_limit)
      else
        v
      end
    end
  end
end
