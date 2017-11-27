module Raven
  class ExceptionInterface < Interface
    attr_accessor :values, :type, :value, :module, :stacktrace

    def self.sentry_alias
      :exception
    end

    def to_hash(*args)
      data = super(*args)
      data[:values] = data[:values].map(&:to_hash) if data[:values]
      data[:stacktrace] = data[:stacktrace].to_hash if data[:stacktrace]
      data
    end

    def self.from_exception(exc, configuration)
      exceptions = exception_chain_to_array(exc)
      backtraces = Set.new
      vals = exceptions.map do |e|
        klass = e.class.to_s

        ExceptionInterface.new do |int|
          int.type = klass
          int.value = e.to_s
          int.module = klass.split('::')[0...-1].join('::')
          int.stacktrace =
            if e.backtrace_locations && !backtraces.include?(e.backtrace_locations.object_id)
              backtraces << e.backtrace.object_id
              StacktraceInterface.new do |stacktrace|
                stacktrace.frames = StacktraceInterface::Frame.from_backtrace(e.backtrace_locations, configuration)
              end
            end
        end
      end

      new(:values => vals)
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
