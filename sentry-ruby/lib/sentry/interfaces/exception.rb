module Sentry
  class ExceptionInterface < Interface
    def initialize(values:)
      @values = values
    end

    def to_hash
      data = super
      data[:values] = data[:values].map(&:to_hash) if data[:values]
      data
    end

    def self.build(exception:, stacktrace_builder:)
      exceptions = Sentry::Utils::ExceptionCauseChain.exception_to_array(exception).reverse
      processed_backtrace_ids = Set.new

      exceptions = exceptions.map do |e|
        if e.backtrace && !processed_backtrace_ids.include?(e.backtrace.object_id)
          processed_backtrace_ids << e.backtrace.object_id
          SingleExceptionInterface.build_with_stacktrace(exception: e, stacktrace_builder: stacktrace_builder)
        else
          SingleExceptionInterface.new(exception: exception)
        end
      end

      new(values: exceptions)
    end
  end
end
