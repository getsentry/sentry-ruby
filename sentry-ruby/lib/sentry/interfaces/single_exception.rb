module Sentry
  class SingleExceptionInterface < Interface
    attr_reader :type, :value, :module, :thread_id, :stacktrace

    def initialize(exception:, stacktrace: nil)
      @type = exception.class.to_s
      @value = (exception.message || "").byteslice(0..Event::MAX_MESSAGE_SIZE_IN_BYTES)
      @module = exception.class.to_s.split('::')[0...-1].join('::')
      @thread_id = Thread.current.object_id
      @stacktrace = stacktrace
    end

    def to_hash
      data = super
      data[:stacktrace] = data[:stacktrace].to_hash if data[:stacktrace]
      data
    end

    # patch this method if you want to change an exception's stacktrace frames
    # also see `StacktraceBuilder.build`.
    def self.build_with_stacktrace(exception:, stacktrace_builder:)
      stacktrace = stacktrace_builder.build(backtrace: exception.backtrace)
      new(exception: exception, stacktrace: stacktrace)
    end
  end
end
