# frozen_string_literal: true

module Sentry
  # @api private
  class LineCache
    def initialize
      @cache = {}
      @context_cache = {}
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

    # Sets context directly on a frame, avoiding intermediate array allocation.
    # Caches results per (filename, lineno) since the same frames repeat across exceptions.
    def set_frame_context(frame, filename, lineno, context)
      cache_key = lineno
      file_contexts = @context_cache[filename]

      if file_contexts
        cached = file_contexts[cache_key]
        if cached
          frame.pre_context = cached[0]
          frame.context_line = cached[1]
          frame.post_context = cached[2]
          return
        end
      end

      lines = getlines(filename)
      return unless lines

      first_line = lineno - context
      pre = Array.new(context) { |i| line_at(lines, first_line + i) }
      ctx_line = line_at(lines, lineno)
      post = Array.new(context) { |i| line_at(lines, lineno + 1 + i) }

      file_contexts = (@context_cache[filename] ||= {})
      file_contexts[cache_key] = [pre, ctx_line, post].freeze

      frame.pre_context = pre
      frame.context_line = ctx_line
      frame.post_context = post
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
