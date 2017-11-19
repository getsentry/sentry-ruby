module Raven
  class StacktraceInterface < Interface
    attr_accessor :frames

    def initialize(*arguments)
      super(*arguments)
    end

    def self.sentry_alias
      :stacktrace
    end

    def to_hash(*args)
      data = super(*args)
      data[:frames] = data[:frames].map(&:to_hash)
      data
    end

    # Not actually an interface, but I want to use the same style
    class Frame < Interface
      APP_DIRS_PATTERN = /(bin|exe|app|config|lib|test)/

      attr_accessor :abs_path, :context_line, :function,
                    :lineno, :module, :pre_context, :post_context, :vars,
                    :project_root, :app_dirs_pattern, :longest_load_path

      def initialize(*arguments)
        super(*arguments)
      end

      def filename
        return if abs_path.nil?
        return @filename if instance_variable_defined?(:@filename)

        @filename = prefix ? abs_path[prefix.to_s.chomp(File::SEPARATOR).length + 1..-1] : abs_path
      end

      def to_hash(*args)
        data = super(*args)
        data[:filename] = filename
        data[:in_app]   = in_app
        [:project_root, :app_dirs_pattern, :longest_load_path].each { |k| data.delete(k) }
        data
      end

      def in_app
        in_app_pattern = Regexp.new("^(#{project_root}/)?#{app_dirs_pattern || APP_DIRS_PATTERN}")
        !!(abs_path =~ in_app_pattern)
      end

      private

      def under_project_root?
        project_root && abs_path.start_with?(project_root)
      end

      def vendored_gem?
        abs_path.match("vendor/bundle")
      end

      def prefix
        if vendored_gem?
          abs_path.match(%r{.*/gems/})
        elsif under_project_root? && in_app
          project_root
        elsif under_project_root?
          longest_load_path || project_root
        else
          longest_load_path
        end
      end
    end
  end
end
