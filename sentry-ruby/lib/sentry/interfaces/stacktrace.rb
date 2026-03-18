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
    # Cache for longest_load_path lookups — shared across all frames
    @load_path_cache = {}
    @load_path_size = nil
    # Cache for compute_filename results — many frames share identical abs_paths
    # Separate caches for in_app=true and in_app=false to avoid composite keys
    @filename_cache_in_app = {}
    @filename_cache_not_in_app = {}
    @filename_project_root = nil

    class << self
      def check_load_path_freshness
        current_size = $LOAD_PATH.size
        if @load_path_size != current_size
          @load_path_cache = {}
          @filename_cache_in_app = {}
          @filename_cache_not_in_app = {}
          @load_path_size = current_size
        end
      end

      def longest_load_path_for(abs_path)
        check_load_path_freshness

        @load_path_cache.fetch(abs_path) do
          result = $LOAD_PATH.select { |path| abs_path.start_with?(path.to_s) }.max_by(&:size)
          @load_path_cache[abs_path] = result
        end
      end

      def cached_filename(abs_path, project_root, in_app, strip_backtrace_load_path)
        return abs_path unless abs_path
        return abs_path unless strip_backtrace_load_path

        check_load_path_freshness

        # Invalidate filename cache when project_root changes
        if @filename_project_root != project_root
          @filename_cache_in_app = {}
          @filename_cache_not_in_app = {}
          @filename_project_root = project_root
        end

        cache = in_app ? @filename_cache_in_app : @filename_cache_not_in_app
        cache.fetch(abs_path) do
          under_root = project_root && abs_path.start_with?(project_root)
          prefix =
            if under_root && in_app
              project_root
            elsif under_root
              longest_load_path_for(abs_path) || project_root
            else
              longest_load_path_for(abs_path)
            end

          result = if prefix
            prefix_str = prefix.to_s
            offset = if prefix_str.end_with?(File::SEPARATOR)
              prefix_str.length
            else
              prefix_str.length + 1
            end
            abs_path.byteslice(offset, abs_path.bytesize - offset)
          else
            abs_path
          end

          cache[abs_path] = result
        end
      end
    end

    class Frame < Interface
      attr_accessor :abs_path, :context_line, :function, :in_app, :filename,
                  :lineno, :module, :pre_context, :post_context, :vars

      def initialize(project_root, line, strip_backtrace_load_path = true)
        @abs_path = line.file
        @function = line.method if line.method
        @lineno = line.number
        @in_app = line.in_app
        @module = line.module_name if line.module_name
        @filename = StacktraceInterface.cached_filename(
          @abs_path, project_root, @in_app, strip_backtrace_load_path
        )
      end

      def to_s
        "#{@filename}:#{@lineno}"
      end

      def compute_filename(project_root, strip_backtrace_load_path)
        return if abs_path.nil?
        return abs_path unless strip_backtrace_load_path

        under_root = project_root && abs_path.start_with?(project_root)
        prefix =
          if under_root && in_app
            project_root
          elsif under_root
            longest_load_path || project_root
          else
            longest_load_path
          end

        if prefix
          prefix_str = prefix.to_s
          offset = if prefix_str.end_with?(File::SEPARATOR)
            prefix_str.length
          else
            prefix_str.length + 1
          end
          abs_path.byteslice(offset, abs_path.bytesize - offset)
        else
          abs_path
        end
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

      def longest_load_path
        StacktraceInterface.longest_load_path_for(abs_path)
      end
    end
  end
end
