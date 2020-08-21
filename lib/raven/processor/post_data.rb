module Raven
  class Processor::PostData < Processor
    def process(data)
      process_if_symbol_keys(data) if data[:request]
      process_if_string_keys(data) if data["request"]

      data
    end

    private

    def process_if_symbol_keys(data)
      return unless data[:request][:method] == "POST"

      data[:request][:data] = STRING_MASK
    end

    def process_if_string_keys(data)
      return unless data["request"]["method"] == "POST"

      data["request"]["data"] = STRING_MASK
    end
  end
end
