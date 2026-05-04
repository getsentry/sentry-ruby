# frozen_string_literal: true

require "securerandom"

module Sentry
  class Profiler
    module Helpers
      def in_app?(abs_path)
        abs_path.match?(@in_app_pattern)
      end

      def compute_filename(abs_path, in_app)
        @filename_cache.compute_filename(abs_path, in_app, true)
      end

      def split_module(name)
        # last module plus class/instance method
        i = name.rindex("::")
        function = i ? name[(i + 2)..-1] : name
        mod = i ? name[0...i] : nil

        [function, mod]
      end
    end
  end
end
