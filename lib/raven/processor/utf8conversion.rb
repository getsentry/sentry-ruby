module Raven
  class Processor::UTF8Conversion < Processor
    def process(value)
      case value
      when Array
        !value.frozen? ? value.map! { |v| process v } : value.map { |v| process v }
      when Hash
        !value.frozen? ? value.merge!(value) { |_, v| process v } : value.merge(value) { |_, v| process v }
      when Exception
        return value if value.message.valid_encoding?
        clean_exc = value.class.new(clean_invalid_utf8_bytes(value.message))
        clean_exc.set_backtrace(value.backtrace)
        clean_exc
      when String
        return value if value.valid_encoding?
        clean_invalid_utf8_bytes(value)
      else
        value
      end
    end

    private

    def clean_invalid_utf8_bytes(obj)
      obj.encode('UTF-16', :invalid => :replace, :undef => :replace, :replace => '').encode('UTF-8')
    end
  end
end
