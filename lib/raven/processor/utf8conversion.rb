module Raven
  class Processor::UTF8Conversion < Processor
    UTF8 = "UTF-8".freeze
    ASCII = "US-ASCII".freeze
    REPLACE = "".freeze

    def process(value)
      case value
      when Hash
        !value.frozen? ? value.merge!(value) { |_, v| process v } : value.merge(value) { |_, v| process v }
      when Array
        !value.frozen? ? value.map! { |v| process v } : value.map { |v| process v }
      when Exception
        return value if utf8_or_subset(value.message) && value.message.valid_encoding?
        clean_exc = value.class.new(remove_invalid_bytes(value.message))
        clean_exc.set_backtrace(value.backtrace)
        clean_exc
      when String
        return value if utf8_or_subset(value) && value.valid_encoding?
        remove_invalid_bytes(value)
      else
        value
      end
    end

    private

    def utf8_or_subset(value)
      [UTF8, ASCII].include?(value.encoding.name)
    end

    # Stolen from RSpec
    # https://github.com/rspec/rspec-support/blob/f0af3fd74a94ff7bb700f6ba06dbdc67bba17fbf/lib/rspec/support/encoded_string.rb#L120-L139
    if String.method_defined?(:scrub) # 2.1+
      def remove_invalid_bytes(string)
        string.scrub!(REPLACE)
      end
    else
      def remove_invalid_bytes(string)
        string.chars.map do |char|
          char.valid_encoding? ? char : REPLACE
        end.join
      end
    end
  end
end
