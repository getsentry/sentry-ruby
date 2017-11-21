module Raven
  class ExceptionInterface < Interface
    attr_accessor :values

    def self.sentry_alias
      :exception
    end

    def to_hash(*args)
      data = super(*args)
      data[:values] = data[:values].map(&:to_hash) if data[:values]
      data
    end

    def self.from_exception(exc, configuration)
      exceptions = exception_chain_to_array(exc)
      backtraces = Set.new
      exceptions.map do |e|
        klass = e.class.to_s

        SingleExceptionInterface.new do |int|
          int.type = klass
          int.value = e.to_s
          int.module = klass.split('::')[0...-1].join('::')

          int.stacktrace =
            if e.backtrace && !backtraces.include?(e.backtrace.object_id)
              backtraces << e.backtrace.object_id
              StacktraceInterface.new do |stacktrace|
                stacktrace.frames = StacktraceInterface::Frame.from_backtrace(e.backtrace, configuration)
              end
            end
        end
      end
    end

    def self.exception_chain_to_array(exc)
      if exc.respond_to?(:cause) && exc.cause
        exceptions = [exc]
        while exc.cause
          exc = exc.cause
          break if exceptions.any? { |e| e.object_id == exc.object_id }
          exceptions << exc
        end
        exceptions.reverse!
      else
        [exc]
      end
    end
  end
end
