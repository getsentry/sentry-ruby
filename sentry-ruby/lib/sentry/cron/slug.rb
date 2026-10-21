# frozen_string_literal: true

module Sentry
  module Cron
    module Slug
      module_function

      # Returns nil when nothing usable is left.
      def from(name)
        slug = name.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").sub(/\A-+/, "")
        slug = slug[0, MonitorCheckIns::MAX_SLUG_LENGTH]
        # rindex instead of /-+\z/, which backtracks on long runs of dashes.
        last = slug.rindex(/[^-]/)
        last && slug[0..last]
      end
    end
  end
end
