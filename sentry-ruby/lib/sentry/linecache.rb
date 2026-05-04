# frozen_string_literal: true

module Sentry
  # @api private
  class LineCache
    def initialize
      @cache = {}
    end

    # Any linecache you provide to Sentry must implement this method.
    # Returns an Array of Strings representing the lines in the source
    # file. The number of lines retrieved is (2 * context) + 1, the middle
    # line should be the line requested by lineno. See specs for more information.
    def get_file_context(filename, lineno, context)
      lines = getlines(filename)
      return nil, nil, nil unless lines

      first_line = lineno - context
      pre = Array.new(context) { |i| line_at(lines, first_line + i) }
      context_line = line_at(lines, lineno)
      post = Array.new(context) { |i| line_at(lines, lineno + 1 + i) }

      [pre, context_line, post]
    end

    private

    def line_at(lines, n)
      return nil if n < 1

      lines[n - 1]
    end

    def getlines(path)
      @cache.fetch(path) do
        @cache[path] = begin
          File.open(path, "r", &:readlines)
        rescue
          nil
        end
      end
    end
  end
end
