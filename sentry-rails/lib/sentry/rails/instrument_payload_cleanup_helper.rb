module Sentry
  module Rails
    module InstrumentPayloadCleanupHelper
      IGNORED_KEYS = [:connection, :binds, :request, :response, :headers, :exception, :exception_object, Tracing::START_TIMESTAMP_NAME]
      ACCEPTABLE_DATA_TYPES = [String, Symbol, Numeric, TrueClass, FalseClass, NilClass, Array, Hash]

      def cleanup_data(data)
        data.delete_if do |key, value|
          IGNORED_KEYS.include?(key) || ACCEPTABLE_DATA_TYPES.none? { |type| value.is_a?(type) }
        end
      end
    end
  end
end
