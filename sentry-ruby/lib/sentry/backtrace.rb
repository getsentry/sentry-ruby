# frozen_string_literal: true

require "rubygems"
require "concurrent/map"
require "sentry/backtrace/line"

module Sentry
  # @api private
  class Backtrace
    # holder for an Array of Backtrace::Line instances
    attr_reader :lines

    def self.parse(backtrace, project_root, app_dirs_pattern, &backtrace_cleanup_callback)
      ruby_lines = backtrace.is_a?(Array) ? backtrace : backtrace.split(/\n\s*/)

      ruby_lines = backtrace_cleanup_callback.call(ruby_lines) if backtrace_cleanup_callback

      in_app_pattern ||= begin
        Regexp.new("^(#{project_root}/)?#{app_dirs_pattern}")
      end

      lines = ruby_lines.to_a.map do |unparsed_line|
        Line.parse(unparsed_line, in_app_pattern)
      end

      new(lines)
    end

    # Thread.each_caller_location is an API added in Ruby 3.2 that doesn't always collect
    # the entire stack like Kernel#caller or #caller_locations do.
    #
    # @see https://github.com/rails/rails/pull/49095 for more context.
    if Thread.respond_to?(:each_caller_location)
      def self.source_location(backtrace_cleaner)
        cache = (line_cache[backtrace_cleaner.__id__] ||= Concurrent::Map.new)

        Thread.each_caller_location do |location|
          frame_key = [location.absolute_path, location.lineno]
          cached_value = cache[frame_key]

          next if cached_value == :skip

          if cached_value
            return cached_value
          else
            cleaned_frame = backtrace_cleaner.clean_frame(location)

            if cleaned_frame
              line = Line.from_source_location(location)
              cache[frame_key] = line

              return line
            else
              cache[frame_key] = :skip

              next
            end
          end
        end
      end

      def self.line_cache
        @line_cache ||= Concurrent::Map.new
      end
    else
      # Since Sentry is mostly used in production, we don't want to fallback
      # to the slower implementation and adds potentially big overhead to the
      # application.
      def self.source_location(*)
        nil
      end
    end


    def initialize(lines)
      @lines = lines
    end

    def inspect
      "<Backtrace: " + lines.map(&:inspect).join(", ") + ">"
    end

    def to_s
      content = []
      lines.each do |line|
        content << line
      end
      content.join("\n")
    end

    def ==(other)
      if other.respond_to?(:lines)
        lines == other.lines
      else
        false
      end
    end
  end
end
