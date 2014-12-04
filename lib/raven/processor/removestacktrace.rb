module Raven
  class Processor::RemoveStacktrace < Processor

    def process(value)
      value[:exception].delete(:stacktrace) if value[:exception]

      value
    end

  end
end
