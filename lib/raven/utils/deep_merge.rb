module Raven
  module Utils
    # ported from ActiveSupport
    module DeepMergeHash
      def self.deep_merge(hash, other_hash, &block)
        deep_merge!(hash, other_hash, &block)
      end

      def self.deep_merge!(hash, other_hash, &block)
        hash.merge!(other_hash) do |key, this_val, other_val|
          if this_val.is_a?(Hash) && other_val.is_a?(Hash)
            deep_merge(this_val, other_val, &block)
          elsif block_given?
            block.call(key, this_val, other_val)
          else
            other_val
          end
        end
      end
    end
  end
end
