# rubocop:disable all
module Raven
  module Utils
    # ported from ActiveSupport
    module DeepMergeHash
      def self.deep_merge(hash, other_hash, &block)
        deep_merge!(hash, other_hash, &block)
      end

      def self.deep_merge!(hash, other_hash, &block)
        other_hash.each_pair do |current_key, other_value|
          this_value = hash[current_key]

          hash[current_key] = if this_value.is_a?(Hash) && other_value.is_a?(Hash)
            this_value.deep_merge(other_value, &block)
          else
            if block_given? && key?(current_key)
              block.call(current_key, this_value, other_value)
            else
              other_value
            end
          end
        end

        hash
      end
    end
  end
end
# rubocop:enable all
