module Raven
  class Processor
    module RequestDataHelper
      def sanitize_request_data(data, verb)
        sanitize_if_string_keys(data, verb) if data["request"]
        sanitize_if_symbol_keys(data, verb) if data[:request]
      end

      private

      def sanitize_if_symbol_keys(data, verb)
        return unless data[:request][:method] == verb
        data[:request][:data] = STRING_MASK
      end

      def sanitize_if_string_keys(data, verb)
        return unless data["request"]["method"] == verb
        data["request"]["data"] = STRING_MASK
      end
    end
  end
end
