# frozen_string_literal: true

require 'json'

module Raven
  class Processor::SanitizeData < Processor
    DEFAULT_FIELDS = %w(authorization password passwd secret ssn social(.*)?sec).freeze
    CREDIT_CARD_RE = /\b(?:3[47]\d|(?:4\d|5[1-5]|65)\d{2}|6011)\d{12}\b/.freeze
    QUERY_STRING = ['query_string', :query_string].freeze
    JSON_STARTS_WITH = ["[", "{"].freeze

    attr_accessor :sanitize_fields, :sanitize_credit_cards, :sanitize_fields_excluded

    def initialize(client)
      super
      self.sanitize_fields = client.configuration.sanitize_fields
      self.sanitize_credit_cards = client.configuration.sanitize_credit_cards
      self.sanitize_fields_excluded = client.configuration.sanitize_fields_excluded
    end

    def process(value, key = nil)
      case value
      when Hash
        sanitize_hash_value(key, value)
      when Array
        sanitize_array_value(key, value)
      when Integer
        matches_regexes?(key, value.to_s) ? INT_MASK : value
      when String
        sanitize_string_value(key, value)
      else
        value
      end
    end

    private

    # CGI.parse takes our nice UTF-8 strings and converts them back to ASCII,
    # so we have to convert them back, again.
    def utf8_processor
      @utf8_processor ||= Processor::UTF8Conversion.new
    end

    def sanitize_hash_value(key, value)
      if key =~ sensitive_fields
        STRING_MASK
      elsif value.frozen?
        value.merge(value) { |k, v| process v, k }
      else
        value.merge!(value) { |k, v| process v, k }
      end
    end

    def sanitize_array_value(key, value)
      if value.frozen?
        value.map { |v| process v, key }
      else
        value.map! { |v| process v, key }
      end
    end

    def sanitize_string_value(key, value)
      if value =~ sensitive_fields && (json = parse_json_or_nil(value))
        # if this string is actually a json obj, convert and sanitize
        process(json).to_json
      elsif matches_regexes?(key, value)
        STRING_MASK
      elsif QUERY_STRING.include?(key)
        sanitize_query_string(value)
      elsif value =~ sensitive_fields
        sanitize_sensitive_string_content(value)
      else
        value
      end
    end

    def sanitize_query_string(query_string)
      query_hash = CGI.parse(query_string)
      sanitized = utf8_processor.process(query_hash)
      processed_query_hash = process(sanitized)
      URI.encode_www_form(processed_query_hash)
    end

    # this scrubs some sensitive info from the string content. for example:
    #
    # ```
    # unexpected token at '{
    # "role": "admin","password": "Abc@123","foo": "bar"
    # }'
    # ```
    #
    # will become
    #
    # ```
    # unexpected token at '{
    # "role": "admin","password": *******,"foo": "bar"
    # }'
    # ```
    #
    # it's particularly useful in hash or param-parsing related errors
    def sanitize_sensitive_string_content(value)
      value.gsub(/(#{sensitive_fields}['":]\s?(:|=>)?\s?)(".*?"|'.*?')/, '\1' + STRING_MASK)
    end

    def matches_regexes?(k, v)
      (sanitize_credit_cards && v =~ CREDIT_CARD_RE) ||
        k =~ sensitive_fields
    end

    def sensitive_fields
      return @sensitive_fields if instance_variable_defined?(:@sensitive_fields)

      fields = DEFAULT_FIELDS | sanitize_fields
      fields -= sanitize_fields_excluded
      @sensitive_fields = /#{fields.map do |f|
        use_boundary?(f) ? "\\b#{f}\\b" : f
      end.join("|")}/i
    end

    def use_boundary?(string)
      !DEFAULT_FIELDS.include?(string) && !special_characters?(string)
    end

    def special_characters?(string)
      REGEX_SPECIAL_CHARACTERS.select { |r| string.include?(r) }.any?
    end

    def parse_json_or_nil(string)
      return unless string.start_with?(*JSON_STARTS_WITH)

      JSON.parse(string)
    rescue JSON::ParserError, NoMethodError
      nil
    end
  end
end
