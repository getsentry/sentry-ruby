module Raven
  class Processor::HTTPHeaders < Processor
    DEFAULT_FIELDS = ["Authorization"].freeze

    attr_accessor :sanitize_http_headers

    def initialize(client)
      super
      self.sanitize_http_headers = client.configuration.sanitize_http_headers
    end

    def process(data)
      process_if_symbol_keys(data) if data[:request]
      process_if_string_keys(data) if data["request"]

      data
    end

    private

    def process_if_symbol_keys(data)
      return unless data[:request][:headers]

      data[:request][:headers].keys.select { |k| fields_re.match(k.to_s) }.each do |k|
        data[:request][:headers][k] = STRING_MASK
      end
    end

    def process_if_string_keys(data)
      return unless data["request"]["headers"]

      data["request"]["headers"].keys.select { |k| fields_re.match(k) }.each do |k|
        data["request"]["headers"][k] = STRING_MASK
      end
    end

    def matches_regexes?(k)
      fields_re.match(k.to_s)
    end

    def fields_re
      @fields_re ||= /#{(DEFAULT_FIELDS | sanitize_http_headers).map do |f|
        use_boundary?(f) ? "\\b#{f}\\b" : f
      end.join("|")}/i
    end

    def use_boundary?(string)
      !DEFAULT_FIELDS.include?(string) && !special_characters?(string)
    end

    def special_characters?(string)
      REGEX_SPECIAL_CHARACTERS.select { |r| string.include?(r) }.any?
    end
  end
end
