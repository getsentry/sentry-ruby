module Raven
  class Processor::UTF8Conversion < Processor
    UTF8 = "UTF-8".freeze
    ASCII = "US-ASCII".freeze
    UTF16 = "UTF-16".freeze
    REPLACE_CHAR = "".freeze

    def process(value)
      case value
      when Array
        value.each { |v| process v }
      when Hash
        value.each { |_, v| process v }
      when Exception
        return value if utf8_or_subset(value.message) && value.message.valid_encoding?
        clean_exc = value.class.new(clean_invalid_utf8_bytes(value.message))
        clean_exc.set_backtrace(value.backtrace)
        clean_exc
      when String
        return value if utf8_or_subset(value) && value.valid_encoding?
        clean_invalid_utf8_bytes(value)
      else
        value
      end
    end

    private

    def utf8_or_subset(value)
      [UTF8, ASCII].include?(value.encoding.name)
    end

    def clean_invalid_utf8_bytes(obj)
      obj.force_encoding(UTF8).encode!(UTF16, :invalid => :replace, :undef => :replace, :replace => REPLACE_CHAR).encode!(UTF8)
    end
  end
end
