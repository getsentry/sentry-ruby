module Sentry
  class ThreadsInterface
    attr_accessor :stacktrace

    def initialize(crashed: false)
      @id = Thread.current.object_id
      @name = Thread.current.name
      @current = true
      @crashed = crashed
    end

    def to_hash
      {
        values: [
          {
            id: @id,
            name: @name,
            crashed: @crashed,
            current: @current,
            stacktrace: @stacktrace&.to_hash
          }
        ]
      }
    end
  end
end
