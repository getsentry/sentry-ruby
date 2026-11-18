# frozen_string_literal: true

require "digest"

module Sentry
  module Cron
    module Slug
      SLUG_HASH_LENGTH = 10

      module_function

      # Sanitize an already-formed key/name into a monitor slug.
      # Returns nil when nothing usable is left.
      def from(name)
        slug = name.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").sub(/\A-+/, "")
        slug = slug[0, MonitorCheckIns::MAX_SLUG_LENGTH]
        # rindex instead of /-+\z/, which backtracks on long runs of dashes.
        last = slug.rindex(/[^-]/)
        last && slug[0..last]
      end

      # Derive a monitor slug from a Ruby class name.
      #
      # @param name [String] fully-qualified class name
      # @param format [Symbol] +:legacy+ (mashed downcase) or +:underscore+ (word breaks)
      # @return [String]
      def from_class_name(name, format: :legacy)
        case format
        when :underscore
          underscore_class_name(name)
        else
          legacy_class_name(name)
        end
      end

      # Current behavior: CamelCase -> lowercased token, +::+ -> +-+, right-truncated.
      def legacy_class_name(name)
        slug = name.to_s.gsub("::", "-").downcase
        slug[-MonitorCheckIns::MAX_SLUG_LENGTH..-1] || slug
      end

      # Rails-style underscore word breaks, +::+ -> +-+.
      # Long slugs keep a hash of the dropped prefix plus a readable tail.
      def underscore_class_name(name)
        slug = name.to_s
          .gsub("::", "-")
          .gsub(/([A-Z]{1,1000})([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase

        return slug if slug.length <= MonitorCheckIns::MAX_SLUG_LENGTH

        # "#{hash}_#{tail}" must fit MAX_SLUG_LENGTH.
        drop_length = slug.length + 1 + SLUG_HASH_LENGTH - MonitorCheckIns::MAX_SLUG_LENGTH
        trim_part = +""

        slug.scan(/([^_-]+)([_-])/) do |segment, separator|
          trim_part << segment << separator
          break if trim_part.length >= drop_length
        end

        trim_part = slug[0, drop_length] if trim_part.length < drop_length

        hash = Digest::SHA256.hexdigest(trim_part)[0, SLUG_HASH_LENGTH]
        "#{hash}_#{slug.delete_prefix(trim_part)}"
      end
    end
  end
end
