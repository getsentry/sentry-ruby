module Sentry
  module Sidekiq
    class ContextFilter
      ACTIVEJOB_RESERVED_PREFIX_REGEX = /^_aj_/.freeze

      def initialize
        @has_global_id = defined?(GlobalID)
      end

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
          if has_global_id? && context.is_a?(GlobalID)
            context.to_s
          else
            context
          end
        end
      end

      private

      def filter_context_hash(key, value)
        key = key.to_s.sub(ACTIVEJOB_RESERVED_PREFIX_REGEX, "") if key.match(ACTIVEJOB_RESERVED_PREFIX_REGEX)
        [key, filter_context(value)]
      end

      def has_global_id?
        @has_global_id
      end
    end
  end
end
