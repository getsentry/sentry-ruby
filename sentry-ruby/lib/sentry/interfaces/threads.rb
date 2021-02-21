module Sentry
  class ThreadsInterface
    def initialize(crashed: false, stacktrace: nil)
      @id = Thread.current.object_id
      @name = Thread.current.name
      @current = true
      @crashed = crashed
      @stacktrace = stacktrace
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

    # patch this method if you want to change a threads interface's stacktrace frames
    # also see `StacktraceBuilder.build`.
    def self.build(backtrace:, stacktrace_builder:, **options)
      stacktrace = stacktrace_builder.build(backtrace: backtrace) if backtrace
      new(**options, stacktrace: stacktrace)
    end
  end
end
