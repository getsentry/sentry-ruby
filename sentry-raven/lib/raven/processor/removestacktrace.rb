module Raven
  class Processor::RemoveStacktrace < Processor
    def process(data)
      process_if_symbol_keys(data) if data[:exception]
      process_if_string_keys(data) if data["exception"]

      data
    end

    private

    def process_if_symbol_keys(data)
      data[:exception][:values].map do |single_exception|
        single_exception.delete(:stacktrace) if single_exception[:stacktrace]
      end
    end

    def process_if_string_keys(data)
      data["exception"]["values"].map do |single_exception|
        single_exception.delete("stacktrace") if single_exception["stacktrace"]
      end
    end
  end
end
