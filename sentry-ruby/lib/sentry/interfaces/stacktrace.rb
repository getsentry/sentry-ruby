# frozen_string_literal: true

module Sentry
  class StacktraceInterface
    # @return [<Array[Frame]>]
    attr_reader :frames

    # @param frames [<Array[Frame]>]
    def initialize(frames:)
      @frames = frames
    end

    # @return [Hash]
    def to_h
      { frames: @frames.map(&:to_h) }
    end

    # @return [String]
    def inspect
      @frames.map(&:to_s)
    end

    private

    # Not actually an interface, but I want to use the same style
    class Frame < Interface
      attr_accessor :abs_path, :context_line, :function, :in_app, :filename,
                  :lineno, :module, :pre_context, :post_context, :vars

      def initialize(project_root, line, strip_backtrace_load_path = true, filename_cache: nil)
        @strip_backtrace_load_path = strip_backtrace_load_path
        @filename_cache = filename_cache

        @abs_path = line.file
        @function = line.method if line.method
        @lineno = line.number
        @in_app = line.in_app
        @module = line.module_name if line.module_name
        @filename = compute_filename
      end

      def to_s
        "#{@filename}:#{@lineno}"
      end

      def compute_filename
        @filename_cache&.compute_filename(abs_path, in_app, @strip_backtrace_load_path)
      end

      def set_context(linecache, context_lines)
        return unless abs_path

        @pre_context, @context_line, @post_context = \
            linecache.get_file_context(abs_path, lineno, context_lines)
      end

      def to_h(*args)
        data = super(*args)
        data.delete(:vars) unless vars && !vars.empty?
        data.delete(:pre_context) unless pre_context && !pre_context.empty?
        data.delete(:post_context) unless post_context && !post_context.empty?
        data.delete(:context_line) unless context_line && !context_line.empty?
        data
      end

      private
    end
  end
end
