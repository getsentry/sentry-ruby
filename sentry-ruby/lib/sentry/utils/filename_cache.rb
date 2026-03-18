# frozen_string_literal: true

module Sentry
  class FilenameCache
    def initialize(project_root)
      @project_root = project_root
      @load_paths = $LOAD_PATH.map(&:to_s).sort_by(&:size).reverse.freeze
      @cache = {}
    end

    def compute_filename(abs_path, in_app, strip_backtrace_load_path)
      return unless abs_path
      return abs_path unless strip_backtrace_load_path

      @cache.fetch(abs_path) do
        under_root = @project_root && abs_path.start_with?(@project_root)
        prefix =
          if under_root && in_app
            @project_root
          elsif under_root
            longest_load_path(abs_path) || @project_root
          else
            longest_load_path(abs_path)
          end

        @cache[abs_path] = if prefix
          offset = if prefix.end_with?(File::SEPARATOR)
            prefix.bytesize
          else
            prefix.bytesize + 1
          end
          abs_path.byteslice(offset, abs_path.bytesize - offset)
        else
          abs_path
        end
      end
    end

    private

    def longest_load_path(abs_path)
      @load_paths.find { |path| abs_path.start_with?(path) }
    end
  end
end
