module Raven
  module Sidekiq
    module ContextFilter
      class << self
        ACTIVEJOB_RESERVED_PREFIX = "_aj_".freeze
        HAS_GLOBALID = const_defined?('GlobalID')

        # Once an ActiveJob is queued, ActiveRecord references get serialized into
        # some internal reserved keys, such as _aj_globalid.
        #
        # The problem is, if this job in turn gets queued back into ActiveJob with
        # these magic reserved keys, ActiveJob will throw up and error. We want to
        # capture these and mutate the keys so we can sanely report it.
        def filter_context(context)
          case context
          when Array
            context.map { |arg| filter_context(arg) }
          when Hash
            Hash[context.map { |key, value| filter_context_hash(key, value) }]
          else
            format_globalid(context)
          end
        end

        private

        def filter_context_hash(key, value)
          (key = key[3..-1]) if key [0..3] == ACTIVEJOB_RESERVED_PREFIX
          [key, filter_context(value)]
        end

        def format_globalid(context)
          if HAS_GLOBALID && context.is_a?(GlobalID)
            context.to_s
          else
            context
          end
        end
      end
    end
  end
end
