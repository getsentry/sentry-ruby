module Raven
  class Processor::RequestMethodData < Processor
    attr_accessor :request_methods

    def initialize(client)
      super
      self.request_methods = client.configuration.sanitize_data_for_request_methods
    end

    def process(data)
      sanitize_if_string_keys(data) if data["request"]
      sanitize_if_symbol_keys(data) if data[:request]

      data
    end

    private

    def sanitize_if_symbol_keys(data)
      return unless sanitize_request_method?(data[:request][:method])
      data[:request][:data] = STRING_MASK
    end

    def sanitize_if_string_keys(data)
      return unless sanitize_request_method?(data["request"]["method"])
      data["request"]["data"] = STRING_MASK
    end

    def sanitize_request_method?(verb)
      request_methods.include?(verb)
    end
  end
end
