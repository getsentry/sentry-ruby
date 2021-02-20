module Sentry
  class SingleExceptionInterface < Interface
    def initialize(exception, stacktrace)
      @type = exception.class.to_s
      @value = exception.message.byteslice(0..Event::MAX_MESSAGE_SIZE_IN_BYTES)
      @module = exception.class.to_s.split('::')[0...-1].join('::')
      @thread_id = Thread.current.object_id
      @stacktrace = stacktrace
    end

    def to_hash
      data = super
      data[:stacktrace] = data[:stacktrace].to_hash if data[:stacktrace]
      data
    end
  end
end
