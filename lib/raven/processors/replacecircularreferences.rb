require 'raven/processor'

module Raven
  module Processor
    class ReplaceCircularReferences < Processor
      def process(data)
        require 'set'
        @seen = Set.new
        replace(data)
      end

      private

      def replace(value)
        oid = value.object_id
        return '<...>' if @seen.include? oid

        @seen << oid
        case value
        when Hash
          value.each.inject({}) do |memo, (k, v)|
            memo[replace(k)] = replace(v)
            memo
          end
        when Array
          value.map do |v|
            replace(v)
          end
        else
          value
        end.tap do
          @seen.delete(oid)
        end
      end
    end
  end
end
