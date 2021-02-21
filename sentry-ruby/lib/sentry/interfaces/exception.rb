module Sentry
  class ExceptionInterface < Interface
    def initialize(values)
      @values = values
    end

    def to_hash
      data = super
      data[:values] = data[:values].map(&:to_hash) if data[:values]
      data
    end

    def self.build(exception:, stacktrace_builder:)
      exceptions = Sentry::Utils::ExceptionCauseChain.exception_to_array(exception).reverse
      backtraces = Set.new

      exceptions = exceptions.map do |e|
        stacktrace =
          if e.backtrace && !backtraces.include?(e.backtrace.object_id)
            backtraces << e.backtrace.object_id
            stacktrace_builder.build(e.backtrace)
          end
        SingleExceptionInterface.new(e, stacktrace)
      end

      new(exceptions)
    end
  end
end
